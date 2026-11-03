// SPDX-License-Identifier: Apache-2.0
import Foundation
@preconcurrency import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

enum VideoMediaError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

/// Owns only an app-created cache directory, never the user's original file.
final class ImportedVideoFile: Transferable, @unchecked Sendable {
    let url: URL
    private let directory: URL

    private init(url: URL, directory: URL) { self.url = url; self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("REUSEVideoImports", isDirectory: true)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try Task.checkCancellation()
            return try copy(from: received.file)
        }
    }

    static func copy(from source: URL, cacheDirectory: URL = cacheRoot) throws -> ImportedVideoFile {
        let manager = FileManager.default
        try manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let size = (try manager.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        try VideoMedia.requireSpace(size + 32 * 1024 * 1024, at: cacheDirectory)
        let directory = cacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let ext = ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "mov"
            let target = directory.appendingPathComponent("input." + ext)
            try manager.copyItem(at: source, to: target)
            return ImportedVideoFile(url: target, directory: directory)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    /// A fresh process has no retained imported movies to resume.
    static func removeOrphans() {
        guard let children = try? FileManager.default.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) else { return }
        for child in children where UUID(uuidString: child.lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: child)
        }
    }
}

struct PreparedVideo: Sendable {
    let file: ImportedVideoFile
    let audioURL: URL
    let duration: CMTime
    let displaySize: CGSize
    var seconds: Double { duration.seconds }
}

struct VideoCompositionParts {
    let composition: AVMutableComposition
    let audioTracks: [AVMutableCompositionTrack]
}

enum VideoMedia {
    static func requireSpace(_ bytes: Int64, at directory: URL) throws {
        let values = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        if let available = values[.systemFreeSize] as? NSNumber, available.int64Value < bytes {
            throw VideoMediaError.message("動画の処理に必要な空き容量がありません。")
        }
    }

    static func containsVideo(_ url: URL) async throws -> Bool {
        try await !AVURLAsset(url: url).loadTracks(withMediaType: .video).isEmpty
    }

    static func prepare(_ file: ImportedVideoFile, maximumSeconds: Double = 300) async throws -> PreparedVideo {
        let asset = AVURLAsset(url: file.url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0.02, duration.seconds <= maximumSeconds else {
            throw VideoMediaError.message("0.02秒より長く、5分以内の動画を選んでください。")
        }
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoMediaError.message("このファイルには映像がありません。")
        }
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoMediaError.message("この動画には音声がありません。")
        }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let descriptions = try await audio.load(.formatDescriptions)
        guard let description = descriptions.first,
              let native = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              native.mSampleRate > 0, native.mSampleRate <= 192000,
              native.mChannelsPerFrame == 1 || native.mChannelsPerFrame == 2 else {
            throw VideoMediaError.message("この動画の音声形式には対応していません。mono／stereoの動画を選んでください。")
        }
        let audioURL = file.url.deletingLastPathComponent().appendingPathComponent("decoded-audio.wav")
        try requireSpace(Int64(ceil(duration.seconds * native.mSampleRate)) * 4 + 32 * 1024 * 1024,
                         at: audioURL.deletingLastPathComponent())
        try extractAudio(asset: asset, track: audio, duration: duration, sampleRate: native.mSampleRate,
                         channels: Int(native.mChannelsPerFrame), destination: audioURL)
        try Task.checkCancellation()
        return PreparedVideo(file: file, audioURL: audioURL, duration: duration,
                             displaySize: CGSize(width: abs(bounds.width), height: abs(bounds.height)))
    }

    /// Decode in small buffers. Timestamp gaps become silence on the movie's timeline.
    private static func extractAudio(asset: AVAsset, track: AVAssetTrack, duration: CMTime,
                                     sampleRate: Double, channels: Int, destination: URL) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw VideoMediaError.message("動画の音声を読み込めません。") }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        guard reader.startReading() else { throw reader.error ?? VideoMediaError.message("動画の音声を読み込めません。") }
        defer { reader.cancelReading() }
        // Decode at the source rate, then let the SDK's AVAudioConverter perform
        // the single high-quality resampling step. Reader-side resampling can
        // return different sample counts and timing for repeated AAC imports.
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        let target = Int(ceil(duration.seconds * sampleRate))
        var written = 0
        func silence(until end: Int) throws {
            while written < end {
                try Task.checkCancellation()
                let count = min(65536, end - written)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                    throw VideoMediaError.message("音声バッファを確保できません。")
                }
                buffer.frameLength = AVAudioFrameCount(count)
                buffer.floatChannelData![0].initialize(repeating: 0, count: count)
                try file.write(from: buffer)
                written += count
            }
        }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let position = CMSampleBufferGetPresentationTimeStamp(sample)
            guard position.isNumeric, let block = CMSampleBufferGetDataBuffer(sample) else {
                throw VideoMediaError.message("動画の音声データが不正です。")
            }
            let offset = Int((position.seconds * sampleRate).rounded())
            let frames = CMSampleBufferGetNumSamples(sample)
            try silence(until: min(target, max(0, offset)))
            let skip = max(0, written - offset)
            let count = min(frames - skip, target - written)
            if count <= 0 { continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw VideoMediaError.message("音声バッファを確保できません。")
            }
            buffer.frameLength = AVAudioFrameCount(count)
            let status: OSStatus
            if channels == 1 {
                status = CMBlockBufferCopyDataBytes(block, atOffset: skip * 4, dataLength: count * 4,
                                                   destination: buffer.floatChannelData![0])
            } else {
                var interleaved = [Float](repeating: 0, count: count * channels)
                status = interleaved.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: skip * channels * 4,
                        dataLength: $0.count, destination: $0.baseAddress!)
                }
                // Averaging preserves the level of dual-mono screen recordings.
                for i in 0..<count {
                    buffer.floatChannelData![0][i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5
                }
            }
            guard status == kCMBlockBufferNoErr else { throw VideoMediaError.message("動画の音声を変換できません。") }
            try file.write(from: buffer)
            written += count
        }
        guard reader.status == .completed else { throw reader.error ?? VideoMediaError.message("動画の音声を最後まで読み込めませんでした。") }
        try silence(until: target)
    }

    static func composition(for source: PreparedVideo, audioURLs: [URL]) async throws -> VideoCompositionParts {
        let asset = AVURLAsset(url: source.file.url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoMediaError.message("動画を開けません。")
        }
        let composition = AVMutableComposition()
        guard let destination = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoMediaError.message("動画の再生を準備できません。")
        }
        let fullRange = CMTimeRange(start: .zero, duration: source.duration)
        let videoRange = CMTimeRangeGetIntersection(try await video.load(.timeRange), otherRange: fullRange)
        try destination.insertTimeRange(videoRange, of: video, at: videoRange.start)
        destination.preferredTransform = try await video.load(.preferredTransform)
        var audioTracks = [AVMutableCompositionTrack]()
        for url in audioURLs {
            let audioAsset = AVURLAsset(url: url)
            guard let track = try await audioAsset.loadTracks(withMediaType: .audio).first,
                  let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoMediaError.message("比較用の音声を開けません。")
            }
            let available = try await track.load(.timeRange)
            let range = CMTimeRangeGetIntersection(available, otherRange: fullRange)
            try target.insertTimeRange(range, of: track, at: range.start)
            audioTracks.append(target)
        }
        return VideoCompositionParts(composition: composition, audioTracks: audioTracks)
    }

    static func export(source: PreparedVideo, enhancedAudio: URL, directory: URL) async throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputBytes = (try manager.attributesOfItem(atPath: source.file.url.path)[.size] as? NSNumber)?.int64Value ?? 0
        try requireSpace(inputBytes + 64 * 1024 * 1024, at: directory)
        // Keep the model's Float32 PCM verbatim. Remuxing separately encoded AAC
        // can drop its priming information and shift the saved audio timeline.
        let parts = try await composition(for: source, audioURLs: [enhancedAudio])
        guard let exporter = AVAssetExportSession(asset: parts.composition, presetName: AVAssetExportPresetPassthrough),
              exporter.supportedFileTypes.contains(.mov) else {
            throw VideoMediaError.message("この形式の動画は書き出せません。")
        }
        let destination = directory.appendingPathComponent("enhanced-video.mov")
        exporter.metadata = []
        exporter.timeRange = CMTimeRange(start: .zero, duration: source.duration)
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: destination, as: .mov)
            try Task.checkCancellation()
            return destination
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }
}
