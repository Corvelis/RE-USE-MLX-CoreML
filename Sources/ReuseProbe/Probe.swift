// SPDX-License-Identifier: Apache-2.0
import Foundation
import ReuseKit

@main
struct Probe {
    struct RunMetadata: Encodable {
        let date: String
        let arguments: [String]
    }
    static func optimization(_ value: String) throws -> ReuseOptimization {
        guard let result = ReuseOptimization(rawValue: value) else {
            throw ReuseError.invalid("Unknown optimization: \(value)")
        }
        return result
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            print("""
            reuse-probe MODEL_PACK INPUT.wav OUTPUT_DIRECTORY [mlx|hybrid] [trials] [optimization]
            reuse-probe MODEL_PACK INPUT.wav OUTPUT_DIRECTORY profile comma,separated,variants
            reuse-probe MODEL_PACK INPUT.wav OUTPUT_DIRECTORY compare mlx|hybrid candidate reference [pairs]
            """)
            return
        }
        let pack = ReuseModelPack(root: URL(fileURLWithPath: args[1]))
        let input = try ReuseAudioFile.read(URL(fileURLWithPath: args[2]), maximumSeconds: 300)
        let destination = URL(fileURLWithPath: args[3], isDirectory: true)
        // Reuse compiled CNNs between comparisons rather than duplicating disk assets.
        let cache = destination.deletingLastPathComponent().appendingPathComponent("cnn-cache")
        try ReuseAudioFile.writeJSON(RunMetadata(date: Date().ISO8601Format(), arguments: args),
            to: destination.appendingPathComponent("run.json"))
        if args.count > 4, args[4] == "profile" {
            guard args.count > 5 else { throw ReuseError.invalid("Provide profiling variants") }
            let variants = try args[5].split(separator: ",").map { try optimization(String($0)) }
            guard !variants.isEmpty else { throw ReuseError.invalid("No profiling variants") }
            let engine = ReuseEngine(modelPack: pack, cacheDirectory: cache, optimization: .warpFast)
            let result = try await engine.diagnose(input.samples,
                progressURL: destination.appendingPathComponent("progress.json"), variants: variants, kernelsOnly: true)
            try ReuseAudioFile.writeJSON(result, to: destination.appendingPathComponent("diagnostics.json"))
            for row in result.rows {
                let values = row.seconds.sorted()
                print("variant=\(row.variant) median_ms=\(values[values.count/2]*1000) relative_rmse=\(row.relativeRMSE)")
            }
            await engine.release()
            return
        }
        if args.count > 4, args[4] == "compare" {
            guard args.count >= 8, let mode = ReuseMode(rawValue: args[5]) else {
                throw ReuseError.invalid("Provide mode, candidate and reference")
            }
            let selected = try optimization(args[6]), reference = try optimization(args[7])
            let rounds = args.count > 8 ? Int(args[8]) ?? 0 : 5
            guard (1...10).contains(rounds) else { throw ReuseError.invalid("Pairs must be between 1 and 10") }
            let baseline = ReuseEngine(modelPack: pack, cacheDirectory: cache, optimization: reference)
            let candidate = ReuseEngine(modelPack: pack, cacheDirectory: cache, optimization: selected)
            try ReuseAudioFile.write(input.samples, to: destination.appendingPathComponent("input.wav"))
            for (name, engine) in [("baseline", baseline), ("candidate", candidate)] {
                let result = try await engine.enhance(input.samples, mode: mode)
                try ReuseAudioFile.writeJSON(result.metrics, to: destination.appendingPathComponent("\(name)_warmup.json"))
                print("warmup=\(name) rtf=\(result.metrics.rtf)"); fflush(stdout)
            }
            var rows = [ReuseMetrics](), participants = [String]()
            for round in 0..<rounds {
                let order = round % 2 == 0 ? [("baseline", baseline), ("candidate", candidate)]
                    : [("candidate", candidate), ("baseline", baseline)]
                for (name, engine) in order {
                    let result = try await engine.enhance(input.samples, mode: mode)
                    try ReuseAudioFile.write(result.samples, to: destination.appendingPathComponent("\(name)_\(round).wav"))
                    rows.append(result.metrics); participants.append(name)
                    try ReuseAudioFile.writeJSON(rows, to: destination.appendingPathComponent("trials.json"))
                    try ReuseAudioFile.writeJSON(participants, to: destination.appendingPathComponent("participants.json"))
                    print("round=\(round) participant=\(name) seconds=\(result.metrics.processingSeconds) rtf=\(result.metrics.rtf)"); fflush(stdout)
                }
            }
            await baseline.release(); await candidate.release()
            return
        }
        guard let mode = args.count > 4 ? ReuseMode(rawValue: args[4]) : .mlx else {
            throw ReuseError.invalid("Unknown mode")
        }
        let count = args.count > 5 ? Int(args[5]) ?? 0 : 3
        guard (1...10).contains(count) else { throw ReuseError.invalid("Trials must be between 1 and 10") }
        let selected = try args.count > 6 ? optimization(args[6]) : .recommended
        let engine = ReuseEngine(modelPack: pack, cacheDirectory: cache, optimization: selected)
        var metrics = [ReuseMetrics]()
        for index in 0...count {
            let result = try await engine.enhance(input.samples, mode: mode)
            try ReuseAudioFile.write(result.samples, to: destination.appendingPathComponent("\(mode.rawValue)_\(index).wav"))
            metrics.append(result.metrics)
            print("trial=\(index) warmup=\(index == 0) processing=\(result.metrics.processingSeconds) rtf=\(result.metrics.rtf)")
            fflush(stdout)
        }
        try ReuseAudioFile.writeJSON(metrics, to: destination.appendingPathComponent("\(mode.rawValue).json"))
        try ReuseAudioFile.writeJSON(input.info, to: destination.appendingPathComponent("input.json"))
        await engine.release()
    }
}
