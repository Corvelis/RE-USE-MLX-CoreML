---
license: openmdw-1.1
base_model: nvidia/NVIDIA-NemotronLabs-RE-USE
pipeline_tag: audio-to-audio
tags:
  - speech-enhancement
  - noise-reduction
  - mlx
  - mlx-swift
  - coreml
  - apple-silicon
  - ios
  - macos
---

# RE-USE for Apple Silicon (MLX + Core ML)

An unofficial Apple Silicon port of [NVIDIA-NemotronLabs-RE-USE](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE) for on-device speech enhancement with ReuseKit on Macs and iPhones.

The same model files work on both platforms. The pack contains MLX weights and Core ML CNN packages. Core ML compiles its packages on each device.

## Commercial use and model identity

**This model permits commercial use under OpenMDW-1.1.** NVIDIA distributes RE-USE releases with different licenses:

| NVIDIA release | Model license | Commercial use |
| --- | --- | --- |
| [Earlier `nvidia/RE-USE`](https://huggingface.co/nvidia/RE-USE) | Noncommercial NSCLv1 | Not permitted |
| [`nvidia/NVIDIA-NemotronLabs-RE-USE`, used by this port](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE) | OpenMDW-1.1 | Permitted, subject to the license terms |

The converted MLX and Core ML models retain OpenMDW-1.1. When redistributing model materials, include the [complete model license](https://huggingface.co/AILogDev/RE-USE-MLX-CoreML/blob/main/LICENSE) and applicable copyright/origin notices. The companion SDK code and original sample recording are Apache-2.0; see the notices in `ReuseKit.zip`.

## Input and output

| Property | Format |
| --- | --- |
| Input | 16 kHz, mono, finite Float32 samples |
| Output | 16 kHz, mono, same sample count |
| Processing | Offline, 5-second windows with 5% overlap |
| Architecture | All 30 stages, full time/frequency resolution, 16 FP32 recurrent states |
| Model assets | 38 files, 54,206,689 bytes |

ReuseKit can read mono/stereo audio files and resample them to 16 kHz. The iPhone sample supports importing or recording up to five minutes, comparison playback at the same position, and Float32 WAV export.

## Swift SDK and samples

[RE-USE-MLX-CoreML on GitHub](https://github.com/Corvelis/RE-USE-MLX-CoreML) provides the Swift SDK, sample apps and usage guides.

[ReuseKit.zip](https://huggingface.co/AILogDev/RE-USE-MLX-CoreML/resolve/main/ReuseKit.zip) contains the Swift package, iPhone sample, Mac CLI, tests, documentation and license notices. The build environment used for validation is Xcode 27.2 / Swift 6.4.2 with the Metal Toolchain.

Download this repository into a directory named `ModelPack`, and extract `ReuseKit.zip` beside it. From the extracted `ReuseKit` directory:

```sh
xcrun swift run --build-system swiftbuild -c release reuse-probe \
  ../ModelPack input.wav output mlx 3
```

This performs one warmup and three measured runs, saving WAV and JSON files. Use `hybrid` instead of `mlx` for the Core ML + MLX mode. On M2, `hybrid 3 foldSeparate` enables the measured faster profile with additional FP16 rounding.

To integrate the Swift API, add the `ReuseKit` package and use:

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

For the iPhone sample, configure `App/ModelSource.json` with this repository's ID and a pinned commit SHA before building. `ModelCatalog.json` contains the download sizes and SHA-256 hashes and matches the catalog bundled with the SDK.

For a private repository, pass a Hugging Face token with read access through the `REUSE_HF_TOKEN` launch environment variable. The sample does not save the token. Keep credentials out of source files and app resources. Downloaded models work offline.

## Execution modes and precision

- **MLX GPU:** runs the full model on the GPU. SSM projections use FP16; recurrent state and normalization use FP32.
- **Core ML + MLX:** runs CNNs through Core ML with `cpuAndNeuralEngine`, and Mamba stages through MLX. CNNs and boundary tensors use FP16. Actual placement is determined by Core ML. Windows without a matching CNN package use MLX.

The checkpoint was converted from NVIDIA's revision `31f82f2efad1095034492f236e8dac9239ba713b`, without additional training. Mixed precision and fused kernels can introduce numerical differences. The recommended profile selects a supported GPU implementation; M2's folded linear-layer profiles are explicit options.

## Measured speed and quality

RTF is processing time divided by input duration; lower is faster.

| Device and mode | Profile | Median RTF |
| --- | --- | ---: |
| iPhone 17 Pro / A19 Pro, Core ML + MLX | `naxFullShared16` | 0.09480 |
| MacBook Air / M2, 8-core GPU, MLX | `foldShared` | 0.19824 |
| MacBook Air / M2, 8-core GPU, Core ML + MLX | `foldSeparate` | 0.14692 |

Measured on iOS/macOS 27.2 using 16 kHz mono, 7.92-second audio, one warmup per profile and five interleaved AB/BA pairs. Timings include STFT, all model stages, iSTFT, overlap-add and GPU completion. File decoding, resampling, model loading, initial compilation and saving are separate costs. Device temperature, input duration and power state affect performance.

On one clean/noisy speech pair, the A19 Pro hybrid profile changed STOI from 0.94836095 to 0.94835503 compared with `warpFast`; the M2 hybrid profile changed it from 0.94833868 to 0.94833576. These measurements cover that pair and synthetic probes. M2's folded profile produced 2.24% additional relative RMSE on a synthetic impulse. Waveform differences depend on the input and are not a percentage of perceived degradation.

The full measurement conditions and profile options are included in the SDK documentation. This is an offline enhancement model, not a streaming microphone API.

## Files and license

- `model_mlx.safetensors`: weights for ReuseKit's MLX architecture.
- `hybrid_front_*.mlpackage` / `hybrid_back_*.mlpackage`: Core ML CNNs.
- `manifest.json`: model identity and asset hashes.
- `ModelCatalog.json`: download file list, sizes and SHA-256 hashes.
- `LICENSE`: NVIDIA's complete OpenMDW-1.1 license and notices.
- `ReuseKit.zip`: Swift SDK and sample source, with its own license notices.

Model materials are distributed under OpenMDW-1.1. Preserve the license and applicable copyright/origin notices when redistributing them. Source model: [NVIDIA-NemotronLabs-RE-USE](https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE).

The companion SDK code and bundled original sample recording are Apache-2.0. See `LICENSE`, `NOTICE` and `licenses/Audio-Samples.txt` inside `ReuseKit.zip` for the license and attribution. Other bundled components retain the terms documented in `licenses`.
