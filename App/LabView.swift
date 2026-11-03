// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UniformTypeIdentifiers
import ReuseKit
import AVKit
import PhotosUI

struct LabView: View {
    @ObservedObject var model: LabModel
    @State private var importing = false
    @State private var showingNotices = false
    @State private var exportingWAV = false
    @State private var exportDocument: WAVExport?
    @State private var deletingModel = false
    @State private var selectedVideo: PhotosPickerItem?
    private let accent = Color(red: 0.05, green: 0.57, blue: 0.55)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    modelCard
                    sourceCard
                    engineCard
                    if !model.modelManaging { actions }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("error")
                    }
                    if let output = model.output { resultCard(output).id("result") }
                    Text("RTF = 処理時間 ÷ 音声の長さ。初回は準備に時間がかかります。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
              }
              .onChange(of: model.busy) { _, busy in
                  if !busy && model.output != nil {
                      withAnimation { proxy.scrollTo("result", anchor: .top) }
                  }
              }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("RE-USE Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNotices = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("このアプリについて")
                }
            }
            .tint(accent)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
                switch result {
                case .success(let url): model.importMedia(url)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .onChange(of: selectedVideo) { _, selection in
                if let selection { model.importVideo(selection); selectedVideo = nil }
            }
            .fileExporter(isPresented: $exportingWAV, document: exportDocument,
                          contentType: .wav, defaultFilename: "RE-USE_ノイズ除去後.wav") { result in
                exportDocument = nil
                if case .failure(let error) = result,
                   (error as NSError).code != NSUserCancelledError {
                    model.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingNotices) { notices }
            .confirmationDialog("モデルを削除しますか？", isPresented: $deletingModel, titleVisibility: .visible) {
                Button("モデルを削除", role: .destructive) { model.deleteDownloadedModel() }
            } message: {
                Text(model.modelSourceConfigured
                    ? "モデルと推論用キャッシュを削除します。再利用にはダウンロードが必要です。録音・WAVは残ります。"
                    : "モデルと推論用キャッシュを削除します。再取得には配布先の公開が必要です。録音・WAVは残ります。")
            }
            }
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ノイズ除去モデル", systemImage: model.modelInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.headline)
                Spacer()
                if model.modelStoredBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: model.modelStoredBytes, countStyle: .file))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text(model.modelMessage).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("modelStatus")
            if model.modelManaging {
                if let value = model.modelTransfer {
                    ProgressView(value: value.fraction).accessibilityIdentifier("modelDownloadProgress")
                    Text(value.phase == .verifying ? "ダウンロードしたモデルを確認中…"
                        : "\(ByteCountFormatter.string(fromByteCount: value.completedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: value.totalBytes, countStyle: .file))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("ダウンロードを停止") { model.stopAll() }
                        .accessibilityIdentifier("cancelModelDownload")
                } else { ProgressView(model.status).font(.caption) }
            } else {
                if !model.modelInstalled {
                    Button { model.downloadModel() } label: {
                        Label(model.modelStoredBytes > 0 ? "ダウンロードを再試行" : "モデルをダウンロード", systemImage: "arrow.down.circle")
                    }.buttonStyle(.borderedProminent)
                        .disabled(!model.modelSourceConfigured || model.busy || model.recording)
                        .accessibilityIdentifier("downloadModel")
                    if model.modelSourceConfigured {
                        Text("約\(ByteCountFormatter.string(fromByteCount: model.modelDownloadBytes, countStyle: .file))。取得後はオフラインで使用できます。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("配布先は公開準備中です。設定後にダウンロードできます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.modelStoredBytes > 0 {
                    Button("モデルを削除", role: .destructive) { deletingModel = true }
                        .disabled(model.busy || model.recording).accessibilityIdentifier("deleteModel")
                }
            }
        }.card()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform").font(.system(size: 32, weight: .medium)).foregroundStyle(accent)
                Spacer()
                Label("端末内で処理", systemImage: "iphone")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(accent.opacity(0.10), in: Capsule()).foregroundStyle(accent)
            }
            Text("声を、もう少しクリアに。")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("NVIDIA RE-USEで動画や音声のノイズを除去し、\n処理前後を聴き比べられます。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("試す動画・音声", systemImage: "waveform").font(.headline)
            HStack(spacing: 8) {
                sourceButton("サンプル", icon: "play.square", action: model.useSample)
                    .disabled(model.recording)
                sourceButton("ファイル", icon: "folder", action: { importing = true })
                    .disabled(model.recording)
                PhotosPicker(selection: $selectedVideo, matching: .videos, preferredItemEncoding: .current) {
                    VStack(spacing: 7) {
                        Image(systemName: "film").font(.system(size: 19, weight: .medium))
                        Text("動画").font(.caption.weight(.semibold))
                    }.frame(maxWidth: .infinity, minHeight: 52).padding(.vertical, 3)
                }.buttonStyle(.bordered).disabled(model.recording).accessibilityIdentifier("source_動画")
                sourceButton(model.recording ? "停止" : "録音", icon: model.recording ? "stop.fill" : "mic", action: model.toggleRecording)
            }
            .disabled(model.busy)
            Text(model.sourceName).font(.subheadline.weight(.medium)).lineLimit(2).accessibilityIdentifier("sourceName")
            if model.recording {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let seconds = Int(model.recordingElapsed)
                    Label(String(format: "%d:%02d / 5:00", seconds / 60, seconds % 60), systemImage: "record.circle")
                        .font(.title2.monospacedDigit()).foregroundStyle(.red)
                }
                Text("停止ボタンで録音を終えられます。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let prepared = model.prepared {
                HStack {
                    Text(String(format: "%.2f秒", prepared.info.preparedSeconds))
                    Spacer()
                    if let video = model.videoSource {
                        Label(String(format: "%.0f × %.0f", video.displaySize.width, video.displaySize.height), systemImage: "film")
                    } else {
                        Text(prepared.info.resampled ? String(format: "%.0f → 16,000 Hz", prepared.info.sourceSampleRate) : "16,000 Hz")
                    }
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if prepared.info.sourceChannels > 1 {
                    Text("stereoをmonoへ変換しました。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Waveform(samples: prepared.samples, color: accent).frame(height: 50)
            } else {
                Text("動画・音声・録音とも最大5分。\n動画は音声のノイズを除去して保存できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.card()
    }

    private func sourceButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 19, weight: .medium))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 52).padding(.vertical, 3)
        }.buttonStyle(.bordered).accessibilityIdentifier("source_\(title)")
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("処理モード").font(.headline)
            Picker("処理モード", selection: $model.mode) {
                Text("ANE + GPU").tag(ReuseMode.hybrid)
                Text("MLX GPU").tag(ReuseMode.mlx)
            }.pickerStyle(.segmented).disabled(model.busy || model.recording)
                .onChange(of: model.mode) { _, _ in model.stopPlayback(); model.clearResult() }
        }.card()
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView(); Text(model.status).font(.subheadline)
                    Spacer()
                    Button("停止") { model.stopAll() }.font(.subheadline.weight(.semibold))
                }.padding(.vertical, 10)
            } else {
                Button { model.run(benchmark: false) } label: {
                    Label("ノイズを除去", systemImage: "sparkles")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(model.prepared == nil || model.recording || !model.modelInstalled)
                    .accessibilityIdentifier("enhance")
                Button { model.run(benchmark: true) } label: {
                    Label("3回でRTFを測る", systemImage: "stopwatch")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.bordered).disabled(model.prepared == nil || model.recording || !model.modelInstalled)
                    .accessibilityIdentifier("benchmark")
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            if model.simulator {
                Text("Simulatorは画面確認用です。推論は実機で実行してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func resultCard(_ result: ReuseResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("結果", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(accent)
                Spacer()
                Text(model.medianRTF == nil ? "今回の実測" : "3回の中央値").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("RTF").font(.headline).foregroundStyle(.secondary)
                Text(String(format: "%.3f", model.medianRTF ?? result.metrics.rtf))
                    .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("rtf")
                Spacer()
                Text(String(format: "%.2f秒で処理", (model.medianRTF ?? result.metrics.rtf)*result.metrics.inputSeconds))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let comparison = model.videoComparison {
                VideoPlayer(player: comparison.player)
                    .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("videoPreview")
                comparisonPicker
                Text("再生中も、同じ位置のまま音声を切り替えられます。")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = model.videoOutputURL {
                    Text("保存形式：MOV").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Button { model.saveVideoToPhotos() } label: {
                            Label(model.savingVideo ? "保存中…" : "写真に保存", systemImage: "square.and.arrow.down")
                        }.disabled(model.savingVideo).accessibilityIdentifier("saveVideo")
                        ShareLink(item: url) { Label("動画を共有", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("shareVideo")
                    }.font(.subheadline)
                }
                if let message = model.videoSaveMessage {
                    Text(message).font(.caption).foregroundStyle(accent)
                }
            } else {
                Waveform(samples: result.samples, color: accent).frame(height: 60)
                comparisonPlayback(duration: result.metrics.inputSeconds)
            }
            Divider()
            HStack {
                Text(String(format: "モデル準備 %.2f秒", result.metrics.modelLoadSeconds))
                Spacer()
                Text(String(format: "MLX最大 %.0f MiB", Double(result.metrics.mlxPeakBytes)/1048576))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                if let url = model.outputURL {
                    Button {
                        do { exportDocument = try WAVExport(url: url); exportingWAV = true }
                        catch { model.error = error.localizedDescription }
                    } label: {
                        Label("WAVを保存", systemImage: "square.and.arrow.down")
                    }.accessibilityIdentifier("saveWAV")
                    ShareLink(item: url) { Label("共有", systemImage: "square.and.arrow.up") }
                }
            }.font(.subheadline)
            if let url = model.reportURL {
                ShareLink(item: url) { Label("計測JSONを共有", systemImage: "doc.text") }.font(.subheadline)
            }
        }.card()
    }

    private func comparisonPlayback(duration: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            comparisonPicker
            HStack(spacing: 14) {
                Button { model.togglePlayback() } label: {
                    Label(model.playbackIsPlaying ? "一時停止" : "再生",
                          systemImage: model.playbackIsPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold)).frame(minWidth: 80).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("comparisonPlay")
                VStack(spacing: 5) {
                    ProgressView(value: min(model.playbackTime, duration), total: max(duration, 0.001))
                    HStack {
                        Text(String(format: "%.1f秒", model.playbackTime))
                        Spacer()
                        Text(String(format: "%.1f秒", duration))
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.accessibilityLabel(String(format: "再生位置 %.1f秒、全体 %.1f秒", model.playbackTime, duration))
            }
            Text("再生中も、同じ位置のまま切り替えられます。")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(model.outputURL == nil || model.busy || model.recording)
    }

    private var comparisonPicker: some View {
        Picker("聴き比べ", selection: Binding(
            get: { model.playbackProcessed }, set: { model.selectPlayback(processed: $0) })) {
            Text("ノイズあり").tag(false)
            Text("ノイズ除去後").tag(true)
        }.pickerStyle(.segmented).accessibilityIdentifier("playbackSource")
            .disabled(model.busy || model.recording)
    }

    private var notices: some View {
        NavigationStack {
            ScrollView {
                Text((try? String(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Notices.txt"), encoding: .utf8)) ?? "NVIDIA RE-USE / SpeechLens / MLX Swift")
                    .font(.caption).textSelection(.enabled).padding(20)
            }.navigationTitle("モデルとライセンス")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showingNotices = false } } }
        }
    }
}

// Export the existing Float32 WAV verbatim; comparison crossfades affect only
// playback and never alter the saved file or run it through another encoder.
private struct WAVExport: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }
    let data: Data
    init(url: URL) throws { data = try Data(contentsOf: url) }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct Waveform: View {
    let samples: [Float]
    let color: Color
    var body: some View {
        Canvas { context, size in
            let bars = 100
            let peak = max(samples.map { abs($0) }.max() ?? 1, 0.001)
            var path = Path()
            for bar in 0..<bars {
                let first = bar*samples.count/bars, last = max(first+1, (bar+1)*samples.count/bars)
                let value = samples.isEmpty ? Float(0) : samples[first..<min(last, samples.count)].map { abs($0) }.max() ?? 0
                let height = max(2, CGFloat(value/peak)*size.height)
                let x = (CGFloat(bar)+0.5)*size.width/CGFloat(bars)
                path.move(to: CGPoint(x: x, y: (size.height-height)/2))
                path.addLine(to: CGPoint(x: x, y: (size.height+height)/2))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }.accessibilityLabel("音声の波形")
    }
}

private extension View {
    func card() -> some View {
        padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
