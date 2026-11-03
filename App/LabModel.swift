// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftUI
import AVFoundation
import ReuseKit
import ReusePlayback
import ReuseModelAssets
import UIKit
import PhotosUI
import Photos

@MainActor
final class LabModel: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    nonisolated static let maximumAudioSeconds: TimeInterval = 300
    @Published var mode: ReuseMode = .hybrid
    @Published var sourceName = "動画・音声を選んでください"
    @Published var prepared: ReuseAudio?
    @Published var output: ReuseResult?
    @Published var busy = false
    @Published var status = "サンプル、ファイル、動画、録音から選べます。"
    @Published var error: String?
    @Published var recording = false
    @Published var playbackProcessed = true
    @Published var playbackIsPlaying = false
    @Published var playbackTime: Double = 0
    @Published var outputURL: URL?
    @Published var inputURL: URL?
    @Published var reportURL: URL?
    @Published var medianRTF: Double?
    @Published var videoSource: PreparedVideo?
    @Published var videoComparison: VideoComparison?
    @Published var videoOutputURL: URL?
    @Published var savingVideo = false
    @Published var videoSaveMessage: String?
    @Published var modelInstalled = false
    @Published var modelManaging = false
    @Published var modelTransfer: ReuseModelTransferProgress?
    @Published var modelStoredBytes: Int64 = 0
    @Published var modelDownloadBytes: Int64 = 0
    @Published var modelSourceConfigured = false
    @Published var modelMessage = "モデルを確認中…"
    private var task: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var player: ComparisonPlayer?
    private var playbackTask: Task<Void, Never>?
    private var audioObservers = [NSObjectProtocol]()
    private var launchHandled = false
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var assets: ReuseModelStore?
    private var modelSource: ReuseModelSource?
    private var engineInstance: ReuseEngine?

    nonisolated private static var launchOptimization: ReuseOptimization {
        let argument = CommandLine.arguments.first { $0.hasPrefix("--reuse-optimization=") }
        return argument.flatMap { ReuseOptimization(rawValue: String($0.dropFirst("--reuse-optimization=".count))) } ?? .recommended
    }

    var simulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    var recordingElapsed: TimeInterval { recorder?.currentTime ?? 0 }

    func useSample() {
        guard !busy, !recording else { return }
        let url = Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav")
        importAudio(url, name: "ノイズを含むサンプル", scoped: false)
    }

    func importAudio(_ url: URL, name: String? = nil, scoped: Bool = true) {
        importMedia(url, name: name, scoped: scoped)
    }

    func importMedia(_ url: URL, name: String? = nil, scoped: Bool = true) {
        guard !busy, !recording else { return }
        stopPlayback(); clearResult(); error = nil; busy = true; status = "ファイルを読み込み中…"
        task = Task {
            let granted = scoped && url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() }; busy = false }
            do {
                if try await VideoMedia.containsVideo(url) {
                    let file = try await Task.detached(priority: .userInitiated) {
                        try ImportedVideoFile.copy(from: url)
                    }.value
                    try await prepareVideo(file)
                    return
                }
                let audio = try await Task.detached(priority: .userInitiated) {
                    try ReuseAudioFile.read(url, maximumSeconds: LabModel.maximumAudioSeconds)
                }.value
                try Task.checkCancellation()
                let input = documents.appendingPathComponent("Current/input16.wav")
                try ReuseAudioFile.write(audio.samples, to: input)
                self.videoSource = nil; self.prepared = audio; self.inputURL = input
                self.sourceName = name ?? url.lastPathComponent
                status = "準備できました。"
            } catch is CancellationError { status = "停止しました。" }
            catch { self.error = error.localizedDescription; status = "音声を読み込めませんでした。" }
        }
    }

    func importVideo(_ selection: PhotosPickerItem) {
        guard !busy, !recording else { return }
        stopPlayback(); clearResult(); error = nil; busy = true; status = "動画を読み込み中…"
        task = Task {
            defer { busy = false }
            do {
                guard let file = try await selection.loadTransferable(type: ImportedVideoFile.self) else {
                    throw VideoMediaError.message("動画を読み込めませんでした。")
                }
                try Task.checkCancellation()
                try await prepareVideo(file)
            } catch is CancellationError { status = "停止しました。" }
            catch { self.error = error.localizedDescription; status = "動画を読み込めませんでした。" }
        }
    }

    private func prepareVideo(_ file: ImportedVideoFile) async throws {
        let source = try await VideoMedia.prepare(file)
        let audio = try await Task.detached(priority: .userInitiated) {
            try ReuseAudioFile.read(source.audioURL, maximumSeconds: LabModel.maximumAudioSeconds + 0.001)
        }.value
        try Task.checkCancellation()
        videoSource = source; prepared = audio; inputURL = source.audioURL
        sourceName = "選択した動画"
        status = "動画の準備ができました。"
    }

    func saveVideoToPhotos() {
        guard !savingVideo, let url = videoOutputURL else { return }
        savingVideo = true; videoSaveMessage = nil; error = nil
        Task {
            defer { savingVideo = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                error = "写真に保存するには、設定で写真への追加を許可してください。共有からファイルにも保存できます。"
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
                }
                videoSaveMessage = "写真に保存しました。"
            } catch { self.error = error.localizedDescription }
        }
    }

    func run(benchmark: Bool) {
        guard !busy, !recording, let audio = prepared else { return }
        guard !simulator else { error = "MLXの推論は実機iPhoneで試してください。Simulatorは画面確認用です。"; return }
        stopPlayback(); clearResult(); error = nil; busy = true
        let selected = mode
        let sourceVideo = videoSource
        task = Task {
            defer { busy = false }
            do {
                let engine = try await requireEngine()
                let directory = documents.appendingPathComponent("Runs/\(UUID().uuidString)")
                var results = [ReuseMetrics](), warmup: ReuseMetrics?
                var finalResult: ReuseResult?
                if benchmark {
                    status = "準備実行 1/1…"
                    warmup = try await engine.enhance(audio.samples, mode: selected).metrics
                }
                let trials = benchmark ? 3 : 1
                for trial in 1...trials {
                    try Task.checkCancellation()
                    status = benchmark ? "計測 \(trial)/\(trials)…" : "ノイズを除去しています…"
                    let result = try await engine.enhance(audio.samples, mode: selected)
                    try Task.checkCancellation()
                    results.append(result.metrics)
                    finalResult = result
                }
                guard let finalResult else { return }
                let wav = directory.appendingPathComponent("enhanced.wav")
                let json = directory.appendingPathComponent("report.json")
                try ReuseAudioFile.write(finalResult.samples, to: wav)
                let report = LabReport(source: audio.info, mode: selected, warmup: warmup, trials: results,
                    device: UIDevice.current.model, identifier: Self.hardwareIdentifier(), date: Date().ISO8601Format())
                try ReuseAudioFile.writeJSON(report, to: json)
                if let sourceVideo {
                    status = "動画を書き出しています…"
                    let movie = try await VideoMedia.export(source: sourceVideo, enhancedAudio: wav, directory: directory)
                    let parts = try await VideoMedia.composition(for: sourceVideo, audioURLs: [sourceVideo.file.url, wav])
                    try Task.checkCancellation()
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback)
                    try session.setActive(true)
                    videoComparison = VideoComparison(parts: parts)
                    observeAudioSession()
                    videoOutputURL = movie
                }
                output = finalResult
                outputURL = wav; reportURL = json
                medianRTF = benchmark ? report.medianRTF : nil
                await refreshModelAssets()
                status = benchmark ? "3回の計測が完了しました。" : "ノイズ除去が完了しました。"
            } catch is CancellationError { status = "停止しました。" }
            catch { self.error = error.localizedDescription; status = "処理を完了できませんでした。" }
        }
    }

    func toggleRecording() {
        guard !busy else { return }
        if recording { recorder?.stop(); return }
        task = Task {
            let permission = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled else { return }
            guard permission else { error = "録音を使うには、設定でマイクへのアクセスを許可してください。"; return }
            do {
                stopPlayback(); clearResult(); error = nil
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                let directory = documents.appendingPathComponent("Recordings")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(UUID().uuidString+".caf")
                recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
                ])
                recorder?.delegate = self
                guard recorder?.record(forDuration: Self.maximumAudioSeconds) == true else { throw ReuseError.invalid("録音を開始できません。") }
                videoSource = nil; prepared = nil; inputURL = nil; sourceName = "マイク録音"
                recording = true; status = "録音中 · 最大5分。停止ボタンで終了できます。"
            } catch { self.error = error.localizedDescription }
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        recording = false
        if flag { importAudio(recorder.url, name: "マイク録音", scoped: false) }
        else { error = "録音を保存できませんでした。" }
    }

    func togglePlayback() {
        guard !busy, !recording else { return }
        do {
            if player == nil {
                guard let before = prepared?.samples, let after = output?.samples else { return }
                player = try ComparisonPlayer(before: before, after: after)
                player?.processed = playbackProcessed
                observeAudioSession()
            }
            guard let player else { return }
            if playbackIsPlaying { pausePlayback(); return }
            try player.play()
            playbackIsPlaying = true
            playbackTask?.cancel()
            playbackTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard let self, let player = self.player else { return }
                    self.playbackTime = player.currentTime
                    if !player.isPlaying {
                        do { try await Task.sleep(for: .seconds(player.drainSeconds)) } catch { return }
                        guard !Task.isCancelled else { return }
                        player.pause(); self.playbackIsPlaying = false
                        return
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func selectPlayback(processed: Bool) {
        playbackProcessed = processed
        player?.processed = processed
        videoComparison?.select(processed: processed)
    }

    private func pausePlayback() {
        videoComparison?.pause()
        player?.pause()
        playbackIsPlaying = false
        playbackTime = player?.currentTime ?? 0
        playbackTask?.cancel(); playbackTask = nil
    }

    private func observeAudioSession() {
        guard audioObservers.isEmpty else { return }
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      type == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in self?.pausePlayback() }
            })
        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                Task { @MainActor in self?.pausePlayback() }
            })
    }

    func stopPlayback() {
        videoComparison?.pause()
        videoComparison?.select(processed: true)
        playbackTask?.cancel(); playbackTask = nil
        player?.stop(); player = nil
        playbackIsPlaying = false; playbackTime = 0; playbackProcessed = true
        audioObservers.forEach(NotificationCenter.default.removeObserver)
        audioObservers.removeAll()
    }
    func clearResult() {
        videoComparison?.stop(); videoComparison = nil; videoOutputURL = nil; videoSaveMessage = nil
        output = nil; outputURL = nil; reportURL = nil; medianRTF = nil
    }
    func stopAll() {
        task?.cancel(); stopPlayback()
        if recording { recorder?.delegate = nil; recorder?.stop(); recorder = nil; recording = false }
    }

    func handleLaunchArguments() async {
        guard !launchHandled else { return }; launchHandled = true
        for (flag, variable) in [("--buffer-ops=", "MLX_MAX_OPS_PER_BUFFER"), ("--buffer-mb=", "MLX_MAX_MB_PER_BUFFER"), ("--cache-mb=", "REUSE_CACHE_MB")] {
            if let argument = CommandLine.arguments.first(where: { $0.hasPrefix(flag) }),
               let value = Int(argument.dropFirst(flag.count)), (1...4096).contains(value) {
                setenv(variable, String(value), 1)
            }
        }
        await configureModelAssets()
        ImportedVideoFile.removeOrphans()
        if CommandLine.arguments.contains("--hf-model-smoke"), !simulator {
            task = Task { await performHuggingFaceSmoke() }
            await task?.value
            return
        }
        if CommandLine.arguments.contains("--model-management-smoke"), !simulator {
            task = Task { await performModelManagementSmoke() }
            await task?.value
            return
        }
        if CommandLine.arguments.contains("--ui-smoke") { useSample(); return }
        if CommandLine.arguments.contains("--speed-compare"), !simulator {
            task = Task { await performSpeedComparison() }
            await task?.value
            return
        }
        if CommandLine.arguments.contains("--speed-profile"), !simulator {
            busy = true; status = "GPUの処理内訳を測定中…"
            defer { busy = false }
            do {
                let engine = try await requireEngine()
                try ReuseAudioFile.writeJSON(["status": "running", "date": Date().ISO8601Format()],
                    to: documents.appendingPathComponent("Speed/run.json"))
                let audio = try ReuseAudioFile.read(Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav"))
                let variants = CommandLine.arguments.first { $0.hasPrefix("--profile-variants=") }
                    .map { String($0.dropFirst("--profile-variants=".count)).split(separator:",").compactMap { ReuseOptimization(rawValue:String($0)) } }
                let report = try await engine.diagnose(audio.samples, progressURL: documents.appendingPathComponent("Speed/progress.json"),
                    variants:variants,kernelsOnly:CommandLine.arguments.contains("--kernels-only"))
                try ReuseAudioFile.writeJSON(report, to: documents.appendingPathComponent("Speed/diagnostics.json"))
                try? FileManager.default.removeItem(at: documents.appendingPathComponent("Speed/error.json"))
                print("REUSE_PROFILE_DONE")
                status = "GPUの測定が完了しました。"
            } catch {
                self.error = error.localizedDescription
                try? ReuseAudioFile.writeJSON(["error": error.localizedDescription], to: documents.appendingPathComponent("Speed/error.json"))
                print("REUSE_PROFILE_FAILED \(error.localizedDescription)")
            }
            return
        }
        guard CommandLine.arguments.contains("--benchmark"), !simulator else { return }
        task = Task { await performLaunchBenchmark() }
        await task?.value
        if CommandLine.arguments.contains("--playback-smoke"), error == nil {
            await performPlaybackSmoke()
        }
    }

    private func performLaunchBenchmark() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let engine = try await requireEngine()
            let paired = CommandLine.arguments.contains("--paired")
            let url = Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav")
            let audio = try ReuseAudioFile.read(url)
            prepared = audio; sourceName = "ノイズを含むサンプル"
            let base = documents.appendingPathComponent(CommandLine.arguments.contains("--speed-run")
                ? "SpeedRuns/\(Self.launchOptimization.rawValue)/\(paired ? "paired" : "sample")"
                : CommandLine.arguments.contains("--playback-smoke") ? "PlaybackSmoke/audio"
                : paired ? "Benchmarks/paired" : "Benchmarks/sample")
            inputURL = base.appendingPathComponent("input16.wav")
            try ReuseAudioFile.write(audio.samples, to: inputURL!)
            var summaries = [LabReport]()
            for selected in ReuseMode.allCases {
                mode = selected; status = "\(selected.title) · 準備実行…"
                let warmup = try await engine.enhance(audio.samples, mode: selected)
                var metrics = [ReuseMetrics]()
                let count = CommandLine.arguments.contains("--quick") ? 1 : 3
                for trial in 1...count {
                    status = "\(selected.title) · 計測 \(trial)/\(count)…"
                    let result = try await engine.enhance(audio.samples, mode: selected)
                    metrics.append(result.metrics); output = result
                    try ReuseAudioFile.write(result.samples, to: base.appendingPathComponent("\(selected.rawValue)_\(trial).wav"))
                }
                let report = LabReport(source: audio.info, mode: selected, warmup: warmup.metrics, trials: metrics,
                    device: UIDevice.current.model, identifier: Self.hardwareIdentifier(), date: Date().ISO8601Format())
                summaries.append(report)
                try ReuseAudioFile.writeJSON(report, to: base.appendingPathComponent("\(selected.rawValue).json"))
                medianRTF = report.medianRTF
                outputURL = base.appendingPathComponent("\(selected.rawValue)_\(count).wav")
            }
            reportURL = base.appendingPathComponent("summary.json")
            try ReuseAudioFile.writeJSON(summaries, to: reportURL!)
            await refreshModelAssets()
            status = "実機計測が完了しました。"
        } catch {
            self.error = error.localizedDescription; status = "計測を完了できませんでした。"
            try? ReuseAudioFile.writeJSON(["error": error.localizedDescription], to: documents.appendingPathComponent("Benchmarks/error.json"))
        }
    }

    private func performPlaybackSmoke() async {
        struct Event: Encodable {
            let action: String
            let before: Double
            let after: Double
            let playing: Bool
        }
        var events = [Event]()
        do {
            togglePlayback()
            guard playbackIsPlaying, let player else { throw ReuseError.invalid("比較再生を開始できませんでした。") }
            for processed in [false, true, false, true] {
                try await Task.sleep(for: .milliseconds(350))
                let before = player.currentTime
                selectPlayback(processed: processed)
                let after = player.currentTime
                guard before > 0, after >= before, after - before < 0.1, player.isPlaying else {
                    throw ReuseError.invalid("切り替え時に再生位置が変わりました。")
                }
                events.append(Event(action: processed ? "processed" : "noisy", before: before, after: after, playing: true))
            }
            pausePlayback()
            let paused = player.currentTime
            try await Task.sleep(for: .milliseconds(200))
            guard player.currentTime == paused else { throw ReuseError.invalid("一時停止中に再生位置が変わりました。") }
            togglePlayback()
            try await Task.sleep(for: .milliseconds(350))
            guard player.currentTime > paused else { throw ReuseError.invalid("続きから再開できませんでした。") }
            events.append(Event(action: "resume", before: paused, after: player.currentTime, playing: player.isPlaying))
            pausePlayback()
            try ReuseAudioFile.writeJSON(events, to: documents.appendingPathComponent("PlaybackSmoke/events.json"))
            status = "同じ位置での切り替え・一時停止・再開を確認しました。"
        } catch {
            self.error = error.localizedDescription
            stopPlayback()
            try? ReuseAudioFile.writeJSON(["error": error.localizedDescription], to: documents.appendingPathComponent("PlaybackSmoke/error.json"))
        }
    }

    private func performSpeedComparison() async {
        busy = true; error = nil
        let comparisonMode: ReuseMode = CommandLine.arguments.contains("--compare-mlx") ? .mlx : .hybrid
        mode = comparisonMode
        defer { busy = false }
        guard let assets else { error = "モデルを準備してください。"; return }
        let pack = ReuseModelPack(root: assets.installedModelDirectory)
        let cache = assets.compilationCacheDirectory
        let reference = CommandLine.arguments.first { $0.hasPrefix("--reference=") }
            .flatMap { ReuseOptimization(rawValue:String($0.dropFirst("--reference=".count))) } ?? .baseline
        let baseline = ReuseEngine(modelPack: pack, cacheDirectory: cache, optimization: reference)
        do {
            let candidate = try await requireEngine()
            let paired = CommandLine.arguments.contains("--paired")
            let probe = CommandLine.arguments.first { $0.hasPrefix("--probe=") }.map { String($0.dropFirst("--probe=".count)) }
            var sourceURL: URL
            if let probe {
                var samples = [Float](repeating: 0,count: probe == "short" ? 1617 : 16000)
                if probe == "impulse" { samples[samples.count/2] = 0.5 }
                else if probe == "quiet" || probe == "short" {
                    for index in samples.indices { samples[index] = Float(sin(Double(index)*0.093)) * (probe == "quiet" ? 1e-5 : 0.1) }
                } else if probe != "silence" { throw ReuseError.invalid("未知の品質テストです。") }
                sourceURL = documents.appendingPathComponent("SpeedFixtures/\(probe).wav")
                try ReuseAudioFile.write(samples,to:sourceURL)
            } else {
                sourceURL = Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav")
            }
            let repeats = CommandLine.arguments.first { $0.hasPrefix("--repeat-sample=") }
                .flatMap { Int($0.dropFirst("--repeat-sample=".count)) } ?? 1
            guard (1...8).contains(repeats) else { throw ReuseError.invalid("音声の繰り返しは1〜8回です。") }
            if repeats > 1 {
                let fixture = try ReuseAudioFile.read(sourceURL)
                sourceURL = documents.appendingPathComponent("SpeedFixtures/repeated_\(repeats).wav")
                try ReuseAudioFile.write(Array(repeating:fixture.samples,count:repeats).flatMap { $0 },to:sourceURL)
            }
            let audio = try ReuseAudioFile.read(sourceURL,maximumSeconds:Self.maximumAudioSeconds)
            let basicLabel = probe.map { "\(comparisonMode.rawValue)_\($0)" }
                ?? (comparisonMode == .mlx ? "mlx_\(paired ? "paired" : "sample")" : paired ? "paired" : "sample")
            let label = basicLabel + (repeats > 1 ? "_repeat\(repeats)" : "")
            let root = documents.appendingPathComponent("SpeedCompare/\(Self.launchOptimization.rawValue)/\(label)")
            prepared = audio; sourceName = "ノイズを含むサンプル"
            inputURL = root.appendingPathComponent("input.wav")
            try ReuseAudioFile.write(audio.samples, to: inputURL!)
            var rows = [ReuseMetrics](),participants = [String]()
            for (name, selected) in [("baseline",baseline),("candidate",candidate)] {
                status = "\(name) · 準備実行…"
                let warmup = try await selected.enhance(audio.samples, mode: comparisonMode)
                try ReuseAudioFile.writeJSON(warmup.metrics, to: root.appendingPathComponent("\(name)_warmup.json"))
            }
            let rounds = CommandLine.arguments.contains("--quick") ? 1 : 5
            for round in 0..<rounds {
                let order = round % 2 == 0 ? [("baseline",baseline),("candidate",candidate)] : [("candidate",candidate),("baseline",baseline)]
                for (name, selected) in order {
                    try Task.checkCancellation()
                    status = "交互比較 \(round+1)/\(rounds) · \(name)…"
                    let result = try await selected.enhance(audio.samples, mode: comparisonMode)
                    rows.append(result.metrics); output = result
                    participants.append(name)
                    let wav = root.appendingPathComponent("\(name)_\(round).wav")
                    try ReuseAudioFile.write(result.samples, to: wav)
                    try ReuseAudioFile.writeJSON(rows, to: root.appendingPathComponent("trials.json"))
                    try ReuseAudioFile.writeJSON(participants, to: root.appendingPathComponent("participants.json"))
                    outputURL = wav
                }
            }
            reportURL = root.appendingPathComponent("trials.json"); medianRTF = nil
            status = "交互比較が完了しました。"
            print("REUSE_COMPARE_DONE \(label)"); fflush(stdout)
        } catch {
            self.error = error.localizedDescription
            try? ReuseAudioFile.writeJSON(["error":error.localizedDescription],
                to: documents.appendingPathComponent("SpeedCompare/\(Self.launchOptimization.rawValue)/error.json"))
            print("REUSE_COMPARE_FAILED \(error.localizedDescription)"); fflush(stdout)
        }
        await baseline.release()
    }

    private static func hardwareIdentifier() -> String {
        var system = utsname(); uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}

// Model storage is independent of recordings and generated WAV files.
extension LabModel {
    private func configureModelAssets() async {
        do {
            let catalogURL = Bundle.main.bundleURL.appendingPathComponent("ModelCatalog.json")
            let catalog = try JSONDecoder().decode(ReuseModelCatalog.self, from: Data(contentsOf: catalogURL))
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let store = try ReuseModelStore(catalog: catalog, applicationSupportDirectory: support, cachesDirectory: caches)
            assets = store; modelDownloadBytes = catalog.totalBytes
            struct Source: Decodable { let repository: String; let revision: String }
            let config = try JSONDecoder().decode(Source.self,
                from: Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("ModelSource.json")))
            let repository = CommandLine.arguments.first { $0.hasPrefix("--model-repository=") }
                .map { String($0.dropFirst("--model-repository=".count)) } ?? config.repository
            let revision = CommandLine.arguments.first { $0.hasPrefix("--model-revision=") }
                .map { String($0.dropFirst("--model-revision=".count)) } ?? config.revision
            if !repository.isEmpty {
                modelSource = try ReuseModelSource(huggingFaceRepository: repository, revision: revision,
                    accessToken: ProcessInfo.processInfo.environment["REUSE_HF_TOKEN"])
            }
            modelSourceConfigured = modelSource != nil
            // Move this app's older CNN cache into the managed namespace once.
            let legacy = caches.appendingPathComponent("ReuseCNN")
            if FileManager.default.fileExists(atPath: legacy.path),
               !FileManager.default.fileExists(atPath: store.compilationCacheDirectory.path) {
                try FileManager.default.createDirectory(at: store.compilationCacheDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: legacy, to: store.compilationCacheDirectory)
            }
        } catch {
            modelMessage = "モデル情報を読み込めませんでした。"
            self.error = error.localizedDescription
        }
        await refreshModelAssets()
    }

    private func refreshModelAssets() async {
        guard let assets else { return }
        do {
            let value = try await assets.inspect()
            modelInstalled = value.isInstalled; modelStoredBytes = value.totalBytes
            modelMessage = value.isInstalled ? "保存済み · オフラインで使用できます。"
                : value.totalBytes > 0 ? "モデルの取得が完了していません。" : "モデルは未ダウンロードです。"
        } catch is CancellationError {} catch {
            modelInstalled = false; modelMessage = "モデルの確認に失敗しました。"
            self.error = error.localizedDescription
        }
    }

    private func requireEngine() async throws -> ReuseEngine {
        guard modelInstalled, let assets else { throw ReuseError.invalid("先にモデルをダウンロードしてください。") }
        if let engineInstance { return engineInstance }
        let value = ReuseEngine(modelPack: ReuseModelPack(root: assets.installedModelDirectory),
            cacheDirectory: assets.compilationCacheDirectory, optimization: Self.launchOptimization)
        engineInstance = value
        return value
    }

    func downloadModel() {
        guard !busy, !recording, let assets, let source = modelSource else { return }
        busy = true; modelManaging = true; error = nil; modelTransfer = nil
        status = "モデルをダウンロードしています…"
        task = Task {
            defer { busy = false; modelManaging = false; modelTransfer = nil }
            do {
                try await assets.download(from: source) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.modelManaging else { return }
                        self.modelTransfer = value
                    }
                }
                await refreshModelAssets()
                status = "モデルの準備ができました。"
            } catch is CancellationError {
                status = "ダウンロードを停止しました。完了済みのファイルは再利用できます。"
                await refreshModelAssets()
            } catch {
                self.error = error.localizedDescription; status = "モデルを取得できませんでした。再試行できます。"
                await refreshModelAssets()
            }
        }
    }

    func deleteDownloadedModel() {
        guard !busy, !recording, let assets else { return }
        stopPlayback(); busy = true; modelManaging = true; error = nil
        status = "モデルを削除しています…"
        task = Task {
            defer { busy = false; modelManaging = false }
            await engineInstance?.release(); engineInstance = nil
            do {
                try await assets.remove()
                let legacy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ReuseCNN")
                if FileManager.default.fileExists(atPath: legacy.path) { try FileManager.default.removeItem(at: legacy) }
                await refreshModelAssets()
                status = "モデルを削除しました。録音とWAVは残っています。"
            } catch { self.error = error.localizedDescription; await refreshModelAssets() }
        }
    }

    /// Physical-device check using a developer-supplied local pack, without publishing or recording.
    private func performModelManagementSmoke() async {
        struct Event: Encodable { let action: String; let installed: Bool; let bytes: Int64 }
        busy = true; modelManaging = true; error = nil
        defer { busy = false; modelManaging = false }
        let fixture = documents.appendingPathComponent("ModelTransferFixture")
        let sentinel = documents.appendingPathComponent("ModelManagementSmoke/audio-retained.txt")
        var events = [Event]()
        do {
            guard let assets else { throw ReuseError.invalid("モデル管理を初期化できません。") }
            try FileManager.default.createDirectory(at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("preserve recordings and WAVs".utf8).write(to: sentinel)
            try await assets.importLocalPack(from: fixture)
            await refreshModelAssets()
            guard modelInstalled else { throw ReuseError.invalid("モデルの取り込みに失敗しました。") }
            let loaded = try await requireEngine()
            let audio = try ReuseAudioFile.read(Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav"))
            let result = try await loaded.enhance(audio.samples, mode: .hybrid)
            try ReuseAudioFile.write(result.samples, to: documents.appendingPathComponent("ModelManagementSmoke/enhanced.wav"))
            try ReuseAudioFile.writeJSON(result.metrics, to: documents.appendingPathComponent("ModelManagementSmoke/metrics.json"))
            await refreshModelAssets()
            events.append(Event(action: "installed-and-inferred", installed: modelInstalled, bytes: modelStoredBytes))
            await loaded.release(); engineInstance = nil
            try await assets.remove()
            await refreshModelAssets()
            guard !modelInstalled, modelStoredBytes == 0, FileManager.default.fileExists(atPath: sentinel.path),
                  FileManager.default.fileExists(atPath: documents.appendingPathComponent("ModelManagementSmoke/enhanced.wav").path) else {
                throw ReuseError.invalid("モデルの削除範囲が不正です。")
            }
            events.append(Event(action: "deleted-model-and-cache-audio-retained", installed: modelInstalled, bytes: modelStoredBytes))
            try await assets.importLocalPack(from: fixture)
            await refreshModelAssets()
            guard modelInstalled else { throw ReuseError.invalid("モデルを復元できません。") }
            try FileManager.default.removeItem(at: fixture)
            events.append(Event(action: "restored-fixture-removed", installed: modelInstalled, bytes: modelStoredBytes))
            try ReuseAudioFile.writeJSON(events, to: documents.appendingPathComponent("ModelManagementSmoke/events.json"))
            useSampleAfterModelSmoke(audio)
            status = "モデルの取得・推論・削除・復元を確認しました。"
            print("REUSE_MODEL_SMOKE_DONE"); fflush(stdout)
        } catch {
            self.error = error.localizedDescription
            try? ReuseAudioFile.writeJSON(["error": error.localizedDescription], to: documents.appendingPathComponent("ModelManagementSmoke/error.json"))
            print("REUSE_MODEL_SMOKE_FAILED \(error.localizedDescription)"); fflush(stdout)
        }
    }

    private func useSampleAfterModelSmoke(_ audio: ReuseAudio) {
        prepared = audio; sourceName = "ノイズを含むサンプル"
    }

    private func performHuggingFaceSmoke() async {
        struct Event: Encodable { let action: String; let installed: Bool; let bytes: Int64 }
        busy = true; modelManaging = true; error = nil
        defer { busy = false; modelManaging = false; modelTransfer = nil }
        let directory = documents.appendingPathComponent("HuggingFaceSmoke")
        let sentinel = directory.appendingPathComponent("audio-retained.txt")
        var events = [Event]()
        do {
            guard let assets, let source = modelSource else { throw ReuseError.invalid("配布先を設定してください。") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("preserve recordings and WAVs".utf8).write(to: sentinel)
            stopPlayback()
            await engineInstance?.release(); engineInstance = nil
            try await assets.remove()
            let anonymous = try ReuseModelSource(huggingFaceRepository: source.repository, revision: source.revision)
            do {
                try await assets.download(from: anonymous)
                throw ReuseError.invalid("非公開モデルを認証なしで取得できてしまいました。")
            } catch let failure as ReuseAssetError {
                guard failure.localizedDescription.contains("HTTP 401") || failure.localizedDescription.contains("HTTP 404") else { throw failure }
            }
            let denied = try await assets.inspect()
            guard !denied.isInstalled else { throw ReuseError.invalid("未認証のモデルが使用可能になっています。") }
            events.append(Event(action: "unauthenticated-download-denied", installed: denied.isInstalled, bytes: denied.totalBytes))
            try await assets.remove()
            let audio = try ReuseAudioFile.read(Bundle.main.bundleURL.appendingPathComponent("Samples/sample_noisy.wav"))
            var originalHash: String?
            for cycle in 1...2 {
                status = "Hugging Faceから取得中 \(cycle)/2…"
                try await assets.download(from: source) { [weak self] progress in
                    Task { @MainActor in self?.modelTransfer = progress }
                }
                await refreshModelAssets()
                guard modelInstalled else { throw ReuseError.invalid("モデルのダウンロードを完了できませんでした。") }
                events.append(Event(action: "downloaded-\(cycle)", installed: modelInstalled, bytes: modelStoredBytes))
                print("REUSE_HF_DOWNLOADED_\(cycle)"); fflush(stdout)
                let loaded = try await requireEngine()
                let result = try await loaded.enhance(audio.samples, mode: .hybrid)
                if let originalHash, originalHash != result.metrics.outputSHA256 {
                    throw ReuseError.invalid("再取得後の推論結果が一致しません。")
                }
                originalHash = result.metrics.outputSHA256
                try ReuseAudioFile.write(result.samples, to: directory.appendingPathComponent("enhanced-\(cycle).wav"))
                try ReuseAudioFile.writeJSON(result.metrics, to: directory.appendingPathComponent("metrics-\(cycle).json"))
                output = result; outputURL = directory.appendingPathComponent("enhanced-\(cycle).wav")
                await loaded.release(); engineInstance = nil
                if cycle == 1 {
                    try await assets.remove()
                    await refreshModelAssets()
                    guard !modelInstalled, modelStoredBytes == 0,
                          FileManager.default.fileExists(atPath: sentinel.path),
                          FileManager.default.fileExists(atPath: outputURL!.path) else {
                        throw ReuseError.invalid("モデルの削除範囲が不正です。")
                    }
                    events.append(Event(action: "deleted-model-and-cache-audio-retained", installed: modelInstalled, bytes: modelStoredBytes))
                }
            }
            await refreshModelAssets()
            try ReuseAudioFile.writeJSON(events, to: directory.appendingPathComponent("events.json"))
            try ReuseAudioFile.writeJSON(["repository": source.repository, "revision": source.revision,
                "outputSHA256": originalHash!], to: directory.appendingPathComponent("source.json"))
            useSampleAfterModelSmoke(audio)
            status = "Hugging Faceからの取得・推論・削除・再取得を確認しました。"
            print("REUSE_HF_SMOKE_DONE"); fflush(stdout)
        } catch {
            self.error = error.localizedDescription
            try? ReuseAudioFile.writeJSON(["error": error.localizedDescription], to: directory.appendingPathComponent("error.json"))
            print("REUSE_HF_SMOKE_FAILED"); fflush(stdout)
        }
    }
}

struct LabReport: Encodable {
    let source: ReuseAudioInfo
    let mode: ReuseMode
    let warmup: ReuseMetrics?
    let trials: [ReuseMetrics]
    let device: String
    let identifier: String
    let date: String
    let medianRTF: Double
    init(source: ReuseAudioInfo, mode: ReuseMode, warmup: ReuseMetrics?, trials: [ReuseMetrics], device: String, identifier: String, date: String) {
        self.source = source; self.mode = mode; self.warmup = warmup; self.trials = trials
        self.device = device; self.identifier = identifier; self.date = date
        let values = trials.map(\.rtf).sorted()
        self.medianRTF = values.isEmpty ? 0 : values[values.count/2]
    }
}
