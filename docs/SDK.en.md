# Swift SDK

[日本語](SDK.md) | English

Use Xcode's “Add Package Dependencies” to specify the repository URL and version, then add the products you need. You can also add a local package. Supported targets are Apple Silicon Macs and physical iPhones. See the [build requirements](BUILDING.en.md).

| Product | Purpose |
| --- | --- |
| `ReuseKit` | Inference and audio file I/O |
| `ReuseModelAssets` | Model download and deletion |
| `ReusePlayback` | Comparison playback that switches between original and enhanced audio at the same position |

To add `ReuseKit` from GitHub to another Swift Package:

```swift
dependencies: [
    .package(url: "https://github.com/Corvelis/RE-USE-MLX-CoreML.git", from: "0.1.0")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: [
        .product(name: "ReuseKit", package: "re-use-mlx-coreml"),
        .product(name: "ReuseModelAssets", package: "re-use-mlx-coreml"),
        .product(name: "ReusePlayback", package: "re-use-mlx-coreml")
    ])
]
```

For a local checkout, replace the package declaration with:

```swift
.package(path: "../RE-USE-MLX-CoreML")
```

Add only the products your app uses.

## Processing an audio file

Provide URLs accessible to your app for `inputURL`, `outputURL`, `modelDirectory` and `cacheDirectory`. `modelDirectory` is the directory containing `manifest.json`; `cacheDirectory` must be writable for Core ML compilation results.

```swift
import Foundation
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

`ReuseAudioFile.read` converts mono or stereo files to 16 kHz mono. The default read limit is 60 seconds. When passing an array directly to `enhance`, provide finite `Float` samples at 16 kHz mono. Input must be longer than 320 samples (0.02 seconds). Output has the same sample count as input.

`ReuseAudioFile.write` saves 16 kHz mono Float32 WAV. `result.metrics.rtf` is the RTF, and `processingSeconds` is the processing time in seconds. Save the metrics as follows:

```swift
try ReuseAudioFile.writeJSON(result.metrics, to: metricsURL)
```

`ReuseEngine` is an actor. Coordinate inference, cancellation and deletion in your app to avoid concurrent operations. To cancel, call `cancel()` on the `Task` that started processing. Before deleting or switching models, wait for processing to finish, call `release()`, and discard references to the engine.

## Execution modes and optimization

`mode: .mlx` runs the full model on the GPU. `.hybrid` runs CNNs through Core ML and the remaining stages through MLX / GPU. See [benchmarks](BENCHMARKS.en.md) for speed and precision comparisons.

The default optimization is `.recommended`. On supported GPUs running iOS 26.2 or later (`applegpu_g18p`, validated on A19 Pro), it selects `.naxFullShared16`. Otherwise, it selects `.warpFast`.

| Profile | Purpose and behavior |
| --- | --- |
| `.recommended` | Automatic selection for the device |
| `.warpFast` | General default path, including on Mac |
| `.foldShared` | Faster MLX GPU execution on M2; combines linear layers with additional FP16 rounding |
| `.foldSeparate` | Faster ANE + GPU execution on M2; also introduces additional FP16 rounding |
| `.residualFuse` | Fuses residual addition without combining linear layers; matched `.warpFast` output on the M2 evaluation recording |

To select a profile explicitly:

```swift
let engine = ReuseEngine(
    modelPack: ReuseModelPack(root: modelDirectory),
    cacheDirectory: cacheDirectory,
    optimization: .foldSeparate
)
let result = try await engine.enhance(audio.samples, mode: .hybrid)
```

Each call processes the supplied audio offline using five-second windows with 5% overlap. A low RTF does not make this a real-time streaming API.

## Downloading and deleting models

Use `installedModelDirectory` from `ReuseModelAssets` for the model location and `compilationCacheDirectory` for the compilation cache. See the [model management guide](MODELS.en.md) for download, progress reporting and deletion code.
