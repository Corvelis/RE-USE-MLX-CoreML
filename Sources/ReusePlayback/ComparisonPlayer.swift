// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CReusePlayback

/// Both signals share one sample cursor and one hardware output stream.
@MainActor
public final class ComparisonPlayer {
    private let engine = AVAudioEngine()
    private let renderer: PlaybackRenderer
    private let node: AVAudioSourceNode
    public let frameCount: Int
    public var isPlaying: Bool { renderer.isPlaying && engine.isRunning }
    public var currentTime: Double { Double(renderer.position) / 16000 }
    public var duration: Double { Double(frameCount) / 16000 }
    // Cursor reaches EOF when the final buffer is submitted, before it is heard.
    // Keep the engine running until the device's queued audio has drained.
    public var drainSeconds: Double {
        #if os(iOS)
        return engine.outputNode.presentationLatency + AVAudioSession.sharedInstance().ioBufferDuration * 2 + 0.05
        #else
        return engine.outputNode.presentationLatency + 0.1
        #endif
    }
    public var processed: Bool {
        get { renderer.processed }
        set { renderer.processed = newValue }
    }

    public init(before: [Float], after: [Float]) throws {
        guard !before.isEmpty, before.count == after.count, before.count < Int(UInt32.max),
              before.allSatisfy(\.isFinite), after.allSatisfy(\.isFinite) else {
            throw PlaybackError.invalidPair
        }
        guard let renderer = before.withUnsafeBufferPointer({ input in
            after.withUnsafeBufferPointer { output in
                PlaybackRenderer(before: input.baseAddress!, after: output.baseAddress!,
                            frameCount: UInt32(before.count), fadeFrames: 160)
            }
        }) else { throw PlaybackError.allocation }
        self.renderer = renderer
        self.frameCount = before.count
        node = renderer.makeSourceNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode,
                       format: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    }

    public func play() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        // Start the engine while silent, then advance the shared transport.
        if !engine.isRunning { try engine.start() }
        renderer.isPlaying = true
    }

    public func pause() {
        renderer.isPlaying = false
        engine.pause()
    }

    public func stop() {
        renderer.isPlaying = false
        engine.stop()
    }
}

public enum PlaybackError: LocalizedError {
    case invalidPair, allocation
    public var errorDescription: String? {
        switch self {
        case .invalidPair: "処理前後で同じ長さの音声が必要です。"
        case .allocation: "比較再生の準備に失敗しました。"
        }
    }
}
