# Release history

[日本語](CHANGELOG.md) | English

## 0.1.0 — 2026-11-02

Initial release for Apple Silicon Macs and iPhones.

- `ReuseKit`: speech enhancement with MLX / Core ML, audio file I/O and RTF measurement.
- `ReuseModelAssets`: model download from Hugging Face, size and SHA-256 verification, and deletion.
- `ReusePlayback`: comparison playback that switches between original and enhanced audio at the same position.
- RE-USE Lab iPhone sample: recording and file import up to five minutes, WAV export and sharing, and speed measurement. ANE + GPU is the initial mode.
- `reuse-probe` Mac CLI: audio processing with WAV output and JSON metrics.
- Japanese and English usage guides, a demo video and an original sample recording.

Supported targets are Apple Silicon Macs running macOS 15 or later and physical iPhones running iOS 18 or later. Builds were validated with Xcode 27.2 (Swift 6.4.2), the Metal Toolchain and Python 3. Both platforms use the same model pack of approximately 54.2 MB, processing audio offline in five-second windows.

The SDK code, sample app code and bundled recording are Apache-2.0. The model is OpenMDW-1.1. See the [licensing guide](docs/LICENSING.en.md) for these terms and dependency licenses.

[Usage and requirements](README.en.md) · [Build instructions](docs/BUILDING.en.md) · [Speed and quality](docs/BENCHMARKS.en.md)
