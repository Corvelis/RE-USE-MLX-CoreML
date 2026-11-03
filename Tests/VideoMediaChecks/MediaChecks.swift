// SPDX-License-Identifier: Apache-2.0
import Foundation
@preconcurrency import AVFoundation

@main struct MediaChecks {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 5, "Expected source, delayed, silent and output paths")
        let root = URL(fileURLWithPath: arguments[4], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let caches = root.appendingPathComponent("imports")
        let original = URL(fileURLWithPath: arguments[1])
        var owned: ImportedVideoFile? = try ImportedVideoFile.copy(from: original, cacheDirectory: caches)
        let ownedURL = owned!.url
        var prepared: PreparedVideo? = try await VideoMedia.prepare(owned!)
        let audio = try AVAudioFile(forReading: prepared!.audioURL)
        precondition(audio.length == Int64(ceil(prepared!.seconds * audio.processingFormat.sampleRate)))
        try FileManager.default.copyItem(at: prepared!.audioURL, to: root.appendingPathComponent("original-extracted.wav"))
        let movie = try await VideoMedia.export(source: prepared!, enhancedAudio: prepared!.audioURL, directory: root.appendingPathComponent("original"))
        let parts = try await VideoMedia.composition(for: prepared!, audioURLs: [original, prepared!.audioURL])
        precondition(parts.audioTracks.count == 2)
        // Native-rate decoding must be deterministic across repeated imports.
        for trial in 0..<3 {
            let repeated = try ImportedVideoFile.copy(from: original, cacheDirectory: caches)
            let result = try await VideoMedia.prepare(repeated)
            try FileManager.default.copyItem(at: result.audioURL,
                to: root.appendingPathComponent("repeated-\(trial).wav"))
        }
        let preview = VideoComparison(parts: parts)
        preview.player.volume = 0
        let item = preview.player.currentItem
        preview.select(processed: false); preview.select(processed: true)
        precondition(preview.player.currentItem === item)
        preview.stop()
        prepared = nil; owned = nil
        precondition(!FileManager.default.fileExists(atPath: ownedURL.path))
        precondition(FileManager.default.fileExists(atPath: original.path))
        let offsetFile = try ImportedVideoFile.copy(from: URL(fileURLWithPath: arguments[2]), cacheDirectory: caches)
        let offset = try await VideoMedia.prepare(offsetFile)
        let input = try AVAudioFile(forReading: offset.audioURL)
        let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length))!
        try input.read(into: buffer)
        let values = buffer.floatChannelData![0]
        let nativeRate = input.processingFormat.sampleRate
        let quietEnd = Int(nativeRate * 0.6875), toneStart = Int(nativeRate * 0.8125), toneEnd = Int(nativeRate * 1.25)
        let silencePeak = (0..<quietEnd).map { abs(values[$0]) }.max()!
        let toneRMS = sqrt((toneStart..<toneEnd).map { Double(values[$0] * values[$0]) }.reduce(0,+) / Double(toneEnd-toneStart))
        precondition(silencePeak < 0.001, "leading audio silence lost: \(silencePeak)")
        precondition(toneRMS > 0.02, "offset audio missing: \(toneRMS)")
        precondition(offset.displaySize.width > offset.displaySize.height, "rotation missing")
        let rotated = try await VideoMedia.export(source: offset, enhancedAudio: offset.audioURL, directory: root.appendingPathComponent("rotated"))
        let noAudioFile = try ImportedVideoFile.copy(from: URL(fileURLWithPath: arguments[3]), cacheDirectory: caches)
        do {
            _ = try await VideoMedia.prepare(noAudioFile)
            preconditionFailure("silent video accepted")
        } catch VideoMediaError.message(let message) { precondition(message.contains("音声がありません")) }
        do {
            _ = try await VideoMedia.prepare(offsetFile, maximumSeconds: 1)
            preconditionFailure("overlong video accepted")
        } catch VideoMediaError.message { }
        let cancellation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoMedia.prepare(offsetFile)
        }
        do { _ = try await cancellation.value; preconditionFailure("cancel ignored") }
        catch is CancellationError { }
        let report: [String: Any] = ["status": "passed", "originalExport": movie.lastPathComponent,
            "rotatedExport": rotated.lastPathComponent, "leadingSilencePeak": silencePeak,
            "offsetToneRMS": toneRMS, "samePlayerItem": true, "ownedCacheRemoved": true,
            "userOriginalPreserved": true, "cancelHandled": true]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("checks.json"))
        print("MEDIA_CHECKS_PASSED")
    }
}
