import XCTest
import AVFoundation
import MLX
@testable import ReuseKit

final class ReuseKitTests: XCTestCase {
    func testNonFiniteHeadsCannotBeHiddenByMagnitudeClamping() throws {
        try Device.withDefaultDevice(.gpu) {
            let invalid = MLXArray.full([1, 321, 201], values: MLXArray(Float.nan))
            let phase = MLXArray.zeros([1, 321, 201])
            let output = Spectral.synthesis(invalid, phase, samples: 16000)
            XCTAssertEqual(output.count, 16000)
            XCTAssertTrue(output.contains { !$0.isFinite })
        }
    }

    func testScanPreservesRangeBeforeOutputProjection() throws {
        try Device.withDefaultDevice(.gpu) {
            // The normalized model output is small even when the preceding
            // state contraction exceeds FP16 range (isolated sounds + silence).
            var gate = [Float16](repeating: 0, count: 1024)
            for i in 256..<512 { gate[i] = 1; gate[i + 512] = 1 }
            var projected = [Float16](repeating: 0, count: 72)
            for direction in 0..<2 {
                for i in 4..<36 { projected[direction * 36 + i] = 1 }
            }
            let kernel = MLXFast.metalKernel(name: "reuse_test_scan_range",
                inputNames: ["xz", "A_log", "projected", "dt_weight", "dt_bias", "u", "Dparam"],
                outputNames: ["out"], source: ReuseKernelSource.scan,
                header: "constant bool TIME_AXIS=true;\n" + ReuseKernelSource.scanHeader)
            let shape = [2, 1, 1, 1, 256]
            let result = kernel([
                MLXArray(gate).reshaped(1, 1, 1, 1024), MLXArray.zeros([512, 16]),
                MLXArray(projected).reshaped(2, 1, 1, 1, 36), MLXArray.zeros([512, 4], dtype: .float16),
                MLXArray.zeros([512]), MLXArray.full(shape, values: MLXArray(Float(30000)), dtype: .float16),
                MLXArray.zeros([512]),
            ], grid: (512, 1, 1), threadGroup: (256, 1, 1), outputShapes: [shape], outputDTypes: [.float32])[0]
            let expected = 16 * log(Float(2)) * 30000 / (1 + exp(Float(-1)))
            let values = result.asArray(Float.self)
            XCTAssertTrue(values.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(values[0], Float(Float16.greatestFiniteMagnitude))
            XCTAssertLessThan(values.map { abs($0 - expected) }.max()!, expected * 0.0001)
        }
    }

    func testSTFTRoundTripAndUncoveredTail() throws {
        try Device.withDefaultDevice(.gpu) {
            let input: [Float] = (0..<16037).map { index in
                let a = Foundation.sin(Double(index)*0.113)
                let b = Foundation.cos(Double(index)*0.047)
                return Float(0.15*a+0.07*b)
            }
            let (amp, phase) = try Spectral.analysis(input)
            XCTAssertEqual(amp.shape, [1, 321, 201])
            let result = Spectral.synthesis(amp, phase, samples: input.count)
            XCTAssertEqual(result.count, input.count)
            let error = zip(result.prefix(16000), input.prefix(16000)).reduce(Float(0)) { max($0, abs($1.0-$1.1)) }
            XCTAssertLessThan(error, 2e-6)
            XCTAssertTrue(result.suffix(37).allSatisfy { $0 == 1e-8 })
        }
    }

    func testFloatWAVRoundTripAndResampling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let samples: [Float] = (0..<16000).map { Float(Foundation.sin(Double($0)*0.12)*0.2) }
        let wav = root.appendingPathComponent("16.wav")
        try ReuseAudioFile.write(samples, to: wav)
        let read = try ReuseAudioFile.read(wav)
        print("IO16 sourceFrames=\(read.info.sourceFrames) prepared=\(read.samples.count) rate=\(read.info.sourceSampleRate) bytes=\(try Data(contentsOf: wav).count)")
        if let destination = ProcessInfo.processInfo.environment["REUSE_IO_DIAGNOSTIC"] {
            try Data(contentsOf: wav).write(to: URL(fileURLWithPath: destination))
        }
        XCTAssertEqual(read.samples.count, samples.count)
        XCTAssertTrue(read.samples == samples, "Float32 WAV changed sample values")
        XCTAssertFalse(read.info.resampled)
        let sourceURL = root.appendingPathComponent("48.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        buffer.frameLength = 48000
        for i in 0..<48000 { buffer.floatChannelData![0][i] = Float(Foundation.sin(Double(i)*0.04)*0.2) }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            try file.write(from: buffer)
            file.close()
        }
        let converted = try ReuseAudioFile.read(sourceURL)
        print("IO48 sourceFrames=\(converted.info.sourceFrames) prepared=\(converted.samples.count) rate=\(converted.info.sourceSampleRate)")
        XCTAssertTrue(converted.info.resampled)
        XCTAssertEqual(converted.samples.count, 16000, accuracy: 2)
        XCTAssertTrue(converted.samples.allSatisfy(\.isFinite))
    }

    func testCancellationBeforeLoading() async throws {
        let pack = ReuseModelPack(root: URL(fileURLWithPath: "/no-such-reuse-pack"))
        let engine = ReuseEngine(modelPack: pack, cacheDirectory: FileManager.default.temporaryDirectory)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await engine.enhance(Array(repeating: 0, count: 16000), mode: .mlx)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testFiveMinuteAudioPreservesEndAndEnforcesLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appendingPathComponent("five-minutes.wav")
        var samples = [Float](repeating: 0, count: 300 * 16000)
        samples[0] = 0.125; samples[samples.count - 1] = -0.375
        try ReuseAudioFile.write(samples, to: wav)
        let audio = try ReuseAudioFile.read(wav, maximumSeconds: 300)
        XCTAssertEqual(audio.samples.count, 4_800_000)
        XCTAssertTrue(audio.samples == samples, "Long recording lost or changed samples")
        XCTAssertThrowsError(try ReuseAudioFile.read(wav)) // SDK default remains 60s.
        samples.append(0.25)
        try ReuseAudioFile.write(samples, to: wav)
        XCTAssertThrowsError(try ReuseAudioFile.read(wav, maximumSeconds: 300))
    }

    func testExactZeroAndTinyCoveredTail() async throws {
        guard let path = ProcessInfo.processInfo.environment["REUSE_MODEL_PACK"] else {
            throw XCTSkip("Set REUSE_MODEL_PACK for the real checkpoint test")
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let engine = ReuseEngine(modelPack: ReuseModelPack(root: URL(fileURLWithPath: path)), cacheDirectory: cache)
        let result = try await engine.enhance(Array(repeating: 0, count: 380160), mode: .mlx)
        XCTAssertEqual(result.samples.count, 380160)
        XCTAssertTrue(result.samples.allSatisfy { $0 == 0 })
        XCTAssertEqual(result.metrics.skippedTinyTailSamples, 160)
        XCTAssertEqual(result.metrics.zeroWindows, 5)
        await engine.release()
    }
}
