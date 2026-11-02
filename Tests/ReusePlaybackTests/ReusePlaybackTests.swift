import XCTest
import AVFoundation
import CReusePlayback
@testable import ReusePlayback

final class ReusePlaybackTests: XCTestCase {
    func testNodeOwnsRendererUntilLastCallbackCanBeReleased() throws {
        var node: AVAudioSourceNode?
        weak var owner: PlaybackRenderer?
        try autoreleasepool {
            let input = [Float](repeating: 0.1, count: 1600)
            let renderer = try XCTUnwrap(input.withUnsafeBufferPointer { buffer in
                PlaybackRenderer(before: buffer.baseAddress!, after: buffer.baseAddress!,
                                 frameCount: 1600, fadeFrames: 160)
            })
            owner = renderer
            node = renderer.makeSourceNode()
        }
        withExtendedLifetime(node) {
            XCTAssertNotNil(owner, "The node must keep its audio buffers alive")
        }
        autoreleasepool { node = nil }
        XCTAssertNil(owner, "Releasing the node must release the buffers")
    }

    func testSwitchUsesSameSampleAndTenMillisecondFade() throws {
        let before = (0..<4000).map { Float($0) / 10000 }
        let after = before.map { $0 + 0.2 }
        let state = try makeState(before, after)
        defer { RABDestroy(state) }
        RABSetPlaying(state, true)
        XCTAssertEqual(render(state, 300), Array(after.prefix(300)))
        RABSetProcessed(state, false)
        let switched = render(state, 320)
        XCTAssertEqual(RABPosition(state), 620)
        for i in 0..<320 {
            let mix = max(Float(0), 1 - Float(i + 1) / 160)
            let expected = before[300 + i] * (1 - mix) + after[300 + i] * mix
            XCTAssertEqual(switched[i], expected, accuracy: 2e-6)
        }
        XCTAssertEqual(Array(switched.suffix(160)), Array(before[460..<620]))
        // Reverse direction midway through another fade. Start at the current
        // gain instead of jumping to either endpoint, and never move the cursor.
        RABSetProcessed(state, true)
        _ = render(state, 80)
        RABSetProcessed(state, false)
        let reversed = render(state, 160)
        XCTAssertEqual(RABPosition(state), 860)
        XCTAssertEqual(reversed[0], before[700] + 0.2 * (0.5 - 0.5 / 160), accuracy: 2e-6)
        XCTAssertEqual(reversed.last!, before[859])
    }

    func testPauseAndSelectionPreserveCursor() throws {
        let before = (0..<2000).map { Float($0) / 10000 }
        let after = before.map { -$0 }
        let state = try makeState(before, after)
        defer { RABDestroy(state) }
        RABSetPlaying(state, true)
        _ = render(state, 615)
        RABSetPlaying(state, false)
        RABSetProcessed(state, false)
        XCTAssertTrue(render(state, 512).allSatisfy { $0 == 0 })
        XCTAssertEqual(RABPosition(state), 615)
        RABSetPlaying(state, true)
        XCTAssertEqual(render(state, 300), Array(before[615..<915]))
        XCTAssertEqual(RABPosition(state), 915)
    }

    func testEndOfFilePadsSilenceAndReplaysFromStart() throws {
        let before: [Float] = [0.1, 0.2, 0.3]
        let after: [Float] = [-0.1, -0.2, -0.3]
        let state = try makeState(before, after)
        defer { RABDestroy(state) }
        RABSetPlaying(state, true)
        XCTAssertEqual(render(state, 8), after + Array(repeating: 0, count: 5))
        XCTAssertFalse(RABIsPlaying(state))
        XCTAssertEqual(RABPosition(state), 3)
        RABSetProcessed(state, false)
        RABSetPlaying(state, true)
        XCTAssertEqual(render(state, 2), Array(before.prefix(2)))
        XCTAssertEqual(RABPosition(state), 2)
    }

    func testSourceNodeThroughActualEngineAndSampleRateConversion() throws {
        let before = (0..<32000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        let after = before.map { $0 * 0.5 }
        let renderer = try XCTUnwrap(before.withUnsafeBufferPointer { input in
            after.withUnsafeBufferPointer { output in
                PlaybackRenderer(before: input.baseAddress!, after: output.baseAddress!, frameCount: 32000, fadeFrames: 160)
            }
        })
        let engine = AVAudioEngine()
        let node = renderer.makeSourceNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
            format: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let outputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 1024)
        try engine.start()
        defer { engine.stop() }
        renderer.isPlaying = true
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024))
        var previous: UInt32 = 0
        for block in 0..<30 {
            if block == 10 || block == 20 { renderer.processed.toggle() }
            XCTAssertEqual(try engine.renderOffline(1024, to: buffer), .success)
            XCTAssertGreaterThanOrEqual(renderer.position, previous)
            XCTAssertLessThanOrEqual(renderer.position - previous, 1024)
            previous = renderer.position
            let audio = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            XCTAssertTrue(audio.allSatisfy(\.isFinite))
        }
        XCTAssertGreaterThan(previous, 9000)
        XCTAssertLessThan(previous, 12000)
    }

    private func makeState(_ before: [Float], _ after: [Float]) throws -> OpaquePointer {
        try XCTUnwrap(before.withUnsafeBufferPointer { input in
            after.withUnsafeBufferPointer { output in
                RABCreate(input.baseAddress!, output.baseAddress!, UInt32(before.count), 160)
            }
        })
    }

    private func render(_ state: OpaquePointer, _ count: Int) -> [Float] {
        var output = [Float](repeating: .nan, count: count)
        output.withUnsafeMutableBufferPointer { _ = RABRender(state, $0.baseAddress!, UInt32(count)) }
        return output
    }
}
