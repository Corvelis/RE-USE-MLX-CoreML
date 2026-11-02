// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import CReusePlayback

/// Controls use C atomics; only the audio render thread advances the cursor.
/// The node owns its renderer through the callback, and the renderer never owns
/// the node. Buffers therefore outlive every callback without a retain cycle.
final class PlaybackRenderer: @unchecked Sendable {
    private let state: OpaquePointer

    init?(before: UnsafePointer<Float>, after: UnsafePointer<Float>,
          frameCount: UInt32, fadeFrames: UInt32) {
        guard let state = RABCreate(before, after, frameCount, fadeFrames) else { return nil }
        self.state = state
    }

    deinit { RABDestroy(state) }

    var processed: Bool {
        get { RABIsProcessed(state) }
        set { RABSetProcessed(state, newValue) }
    }
    var isPlaying: Bool {
        get { RABIsPlaying(state) }
        set { RABSetPlaying(state, newValue) }
    }
    var position: UInt32 { RABPosition(state) }

    func makeSourceNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        return AVAudioSourceNode(format: format) { [self] isSilence, _, count, buffers in
            guard let data = buffers.pointee.mBuffers.mData else {
                isSilence.pointee = true
                return noErr
            }
            // The callback only accesses the C state and its preallocated buffers.
            let rendered = RABRender(state, data.assumingMemoryBound(to: Float.self), count)
            isSilence.pointee = ObjCBool(rendered == 0)
            return noErr
        }
    }
}
