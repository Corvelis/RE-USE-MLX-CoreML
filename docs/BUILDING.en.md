# Building and running the samples

[日本語](BUILDING.md) | English

Install Xcode, the Metal Toolchain and Python 3. Builds were validated with Xcode 27.2 (Swift 6.4.2). Run the following commands from the directory containing `Package.swift`.

## iPhone app

1. Review the [model source and access settings](MODELS.en.md).
2. Enable Developer Mode on your iPhone and connect it to your Mac.
3. Build with your Apple Developer Team ID.

```sh
zsh build_app.sh iphoneos -allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

Replace `YOUR_TEAM_ID` with your Team ID. Package dependencies are fetched during the build. Have at least 2 GiB of free space before building, with room for dependencies and build products.

Open the generated Xcode project with:

```sh
open .build/app/ReuseLab.xcodeproj
```

App build products are stored in `.build/app`. To use a different location, set `REUSE_BUILD_DIR` and use the same value when installing.

List connected devices, then install using the device's name or identifier:

```sh
xcrun devicectl list devices
zsh install_app.sh "DEVICE_NAME_OR_ID"
```

To preview the interface in the Simulator:

```sh
zsh build_app.sh iphonesimulator CODE_SIGNING_ALLOWED=NO
```

Run inference and speed measurements on a physical iPhone.

## Mac command-line sample

With `hf` from the [Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/en/guides/cli), download the matching model files as follows:

```sh
hf download AILogDev/RE-USE-MLX-CoreML \
  --revision 4b7e50680ba34f10865cab7e24054262596f5ab4 \
  --local-dir ModelPack \
  --include manifest.json model_mlx.safetensors 'hybrid_*.mlpackage/*'
```

For a private model, run `hf auth login` with an account that has access before downloading. If using another download method, obtain the complete [model pack](MODELS.en.md), including the files inside each `.mlpackage`.

On Mac, use the Swift Build engine in Swift 6.4 or later to build the executable and MLX Metal shaders:

```sh
xcrun swift build --build-system swiftbuild -c release --product reuse-probe
```

Pass the model directory, input audio and output directory to `swift run`:

```sh
xcrun swift run --build-system swiftbuild -c release reuse-probe \
  ModelPack App/Samples/sample_noisy.wav output mlx 3
```

This example processes the bundled recording. If the model is stored elsewhere, replace `ModelPack` with the directory containing `manifest.json`. To try your own audio, replace `App/Samples/sample_noisy.wav` with your input file. Input is converted to 16 kHz mono, with a maximum duration of five minutes. The argument `3` requests one warmup followed by three measured runs. The output directory receives a WAV file for each run and JSON files containing RTF and other metrics.

Replace `mlx` with `hybrid` to use ANE + GPU. For example, to select the faster profile measured on M2:

```sh
xcrun swift run --build-system swiftbuild -c release reuse-probe \
  MODEL_DIRECTORY input.wav output-hybrid hybrid 3 foldSeparate
```

See the [SDK guide](SDK.en.md) for profile selection and numerical differences, and [benchmarks](BENCHMARKS.en.md) for measurement conditions.

## Metal Toolchain

If Xcode requests the Metal Toolchain, install it with:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Tests

Run the SDK and comparison playback tests on Mac. GPU tests require an Apple Silicon Mac.

```sh
xcrun swift test --build-system swiftbuild -c release -j 4
```

For tests that use the actual checkpoint, set `REUSE_MODEL_PACK` to the model directory. To run only the model management tests, use:

```sh
python3 test_model_assets.py
```

To verify the bundled sample's contents and metadata:

```sh
python3 verify_sample.py
```

To check video import and export, install FFmpeg on the Mac and run the command below. The checks generate a short picture and tone, then verify audio timing and level, video and orientation preservation, the comparison player, cancellation and working-copy cleanup.

```sh
python3 test_video_media.py
```

GitHub Actions checks model management, video import and export, bundled sample integrity, license notices, helper scripts and Xcode project generation.
