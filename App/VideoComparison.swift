// SPDX-License-Identifier: Apache-2.0
import Foundation
@preconcurrency import AVFoundation
import Combine

/// A single player item owns the video and both sample-aligned audio tracks.
@MainActor
final class VideoComparison: ObservableObject {
    let player: AVPlayer
    let item: AVPlayerItem
    private let tracks: [AVMutableCompositionTrack]
    private var settleTask: Task<Void, Never>?
    private var jumpObserver: NSObjectProtocol?
    private(set) var processed = true

    init(parts: VideoCompositionParts) {
        tracks = parts.audioTracks
        item = AVPlayerItem(asset: parts.composition)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        item.audioMix = Self.mix(tracks: tracks, from: true, to: true, at: nil)
        jumpObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemTimeJumped, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.settleMix() }
        }
    }

    func select(processed next: Bool) {
        guard next != processed else { return }
        let previous = processed
        processed = next
        settleTask?.cancel()
        let time = player.currentTime()
        item.audioMix = Self.mix(tracks: tracks, from: previous, to: next,
                                 at: player.rate > 0 && time.isNumeric ? time : nil)
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.settleMix()
        }
    }

    private func settleMix() {
        settleTask?.cancel(); settleTask = nil
        item.audioMix = Self.mix(tracks: tracks, from: processed, to: processed, at: nil)
    }

    func pause() { player.pause() }

    func stop() {
        settleTask?.cancel(); settleTask = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver); self.jumpObserver = nil }
    }

    private static func mix(tracks: [AVMutableCompositionTrack], from: Bool, to: Bool, at time: CMTime?) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.enumerated().map { index, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            let start: Float = (index == 1) == from ? 1 : 0
            let end: Float = (index == 1) == to ? 1 : 0
            parameters.setVolume(time == nil ? end : start, at: .zero)
            if let time {
                parameters.setVolumeRamp(fromStartVolume: start, toEndVolume: end,
                    timeRange: CMTimeRange(start: time, duration: CMTime(seconds: 0.025, preferredTimescale: 60000)))
            }
            return parameters
        }
        return mix
    }
}
