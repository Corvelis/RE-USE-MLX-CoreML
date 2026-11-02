# RE-USE-MLX-CoreML

[日本語](README.md) | English

An unofficial Apple Silicon port of NVIDIA RE-USE. The Swift library and samples run speech enhancement on Macs and iPhones using the same model files, with all audio processing on the device.

Download the model from [RE-USE for Apple Silicon (MLX + Core ML)](https://huggingface.co/AILogDev/RE-USE-MLX-CoreML). For private model access, see the [model management guide](docs/MODELS.en.md#trying-a-private-model).

| Component | Purpose |
| --- | --- |
| `ReuseKit` | MLX / Core ML inference, audio file I/O and RTF measurement |
| `ReuseModelAssets` | Model download from Hugging Face, integrity verification and deletion |
| `ReusePlayback` | Comparison playback that switches between original and enhanced audio at the same position |
| RE-USE Lab | SwiftUI sample app for iPhone |
| `reuse-probe` | Command-line sample for Mac |

The directory containing `Package.swift` is the package root. `Sources` contains the SDK and Mac CLI, `Tests` contains tests, `App` contains the iPhone sample, and `docs` contains the usage guides.

## Requirements

- Apple Silicon Mac: macOS 15 or later.
- Physical iPhone: iOS 18 or later.
- Build validation environment: Xcode 27.2 (Swift 6.4.2), Metal Toolchain and Python 3.
- Model: approximately 54.2 MB. Additional space is needed for Core ML compilation caches.

MLX Swift is pinned to 0.33.0. Use the Simulator to preview the interface and a physical device for inference.

## Using the Swift SDK

In Xcode's “Add Package Dependencies,” add the `main` branch of `https://github.com/Corvelis/RE-USE-MLX-CoreML.git` and select `ReuseKit`. After downloading the [model files](docs/BUILDING.en.md#mac-command-line-sample), process an audio file as follows:

```swift
import ReuseKit

let audio = try ReuseAudioFile.read(inputURL, maximumSeconds: 300)
let engine = ReuseEngine(
    modelPack: ReuseModelPack(root: modelDirectory),
    cacheDirectory: cacheDirectory
)
let result = try await engine.enhance(audio.samples, mode: .mlx)
try ReuseAudioFile.write(result.samples, to: outputURL)
await engine.release()
```

See the [SDK guide](docs/SDK.en.md) for URL setup, processing modes, and model download and deletion.

## Using the iPhone app

The sample app's interface is in Japanese. The button labels below match those shown in the app.

Before building, review the [model source and access settings](docs/MODELS.en.md), then follow the [build instructions](docs/BUILDING.en.md) to install the app.

1. Tap “モデルをダウンロード” (Download model). Once downloaded, the model works offline.
2. Select audio with “ファイル” (File) or record with the microphone. Both support up to five minutes.
3. Select a processing mode and tap “ノイズを除去” (Remove noise).
4. Play the result. Switch between “ノイズあり” (Original) and “ノイズ除去後” (Enhanced) without changing the playback position.
5. Export the enhanced audio with “WAVを保存” (Save WAV) or “共有” (Share).

Input is converted to 16 kHz mono. Output is 16 kHz mono Float32 WAV. “3回でRTFを測る” (Measure RTF over three runs) performs one warmup and three measured runs; you can share the resulting JSON. Recording, playback, processing and downloads stop when the app moves to the background.

“モデルを削除” (Delete model) removes the model files, partial downloads and Core ML compilation caches. Recordings, enhanced WAV files and measurement results are retained. Download the model again to resume enhancement.

## Processing modes

| Mode | Execution | When to use |
| --- | --- | --- |
| ANE + GPU | Runs CNNs through Core ML and Mamba stages through MLX / GPU | Default in the iPhone app |
| MLX GPU | Runs the full model on the GPU | Use the GPU only |

Both modes retain all 30 stages, 16 FP32 recurrent states, five-second processing windows and 5% overlap. ANE + GPU uses FP16 for CNNs and boundary tensors, so its output differs from MLX GPU. The OS determines actual Core ML placement. Windows without a matching CNN shape use MLX.

Audio is processed offline. Continuous conversion of live microphone input requires additional streaming support.

## Processing speed

RTF is processing time divided by audio duration. An RTF of 0.1 means approximately one second of processing for ten seconds of audio.

| Device | Mode | Median RTF |
| --- | --- | ---: |
| iPhone 17 Pro / A19 Pro | ANE + GPU, automatic profile selection | 0.0948 |
| MacBook Air / M2, 8-core GPU | MLX GPU, `foldShared` | 0.1982 |
| MacBook Air / M2, 8-core GPU | ANE + GPU, `foldSeparate` | 0.1469 |

Measured after warmup using 16 kHz mono audio lasting 7.92 seconds. The Mac results use explicitly selected optimization profiles. Initial preparation, input duration and device temperature affect processing time. See the [measurement conditions and quality comparisons](docs/BENCHMARKS.en.md).

## Developer guides

- [Building and running the Mac sample](docs/BUILDING.en.md)
- [Integrating the Swift SDK](docs/SDK.en.md)
- [Model distribution, download and deletion](docs/MODELS.en.md)
- [Speed and quality measurements](docs/BENCHMARKS.en.md)

## Exporting the source package

```sh
python3 export_source.py dist/ReuseKit --archive
```

This creates `dist/ReuseKit` and `dist/ReuseKit.zip`, containing the SDK, samples, tests, usage guides and licenses. The exported directory can be used directly as a Swift Package repository.

## Licenses and attribution

The SDK code, sample app code and bundled recording are [Apache-2.0](LICENSE). The model is OpenMDW-1.1. See the [audio attribution](licenses/Audio-Samples.txt), [distribution requirements](docs/LICENSING.en.md) and [Third-Party Notices](App/Notices.txt). The app's information button also displays the full notices.
