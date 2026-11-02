# Model distribution and management

[日本語](MODELS.md) | English

Macs and iPhones use the same model pack. Distribute the MLX weights and Core ML `.mlpackage` files; Core ML compiles its packages on each device.

The matching model is specified in [ModelCatalog.json](../App/ModelCatalog.json): 38 files totaling 54,206,689 bytes (approximately 54.2 MB). The catalog contains each file's size and SHA-256 hash.

## Preparing files for Hugging Face

To verify local model sizes and SHA-256 hashes and prepare the model card, license and SDK source:

```sh
python3 export_source.py dist/ReuseKit --archive
python3 prepare_model_release.py MODEL_DIRECTORY dist/ModelPack \
  --sdk-archive dist/ReuseKit.zip
```

Replace `MODEL_DIRECTORY` with the model directory containing `manifest.json`. The generated `dist/ModelPack` contains the distribution files. These commands create local files.

Upload the following structure to a Hugging Face model repository. Include all files inside each `.mlpackage` folder. For general distribution, make the repository public so downloads work without authentication.

```text
manifest.json
model_mlx.safetensors
hybrid_front_*.mlpackage/
hybrid_back_*.mlpackage/
README.md
LICENSE
ModelCatalog.json
ReuseKit.zip
```

The model card should describe intended use, input and output formats, the source model, conversion details and measurement conditions. Use the [complete NVIDIA model license](../licenses/NVIDIA-RE-USE.txt) as `LICENSE` and set the model card license to `openmdw-1.1`. The source is NVIDIA RE-USE revision `31f82f2efad1095034492f236e8dac9239ba713b`. See the [distribution requirements](LICENSING.en.md).

Distributed files must match the catalog's sizes and hashes. To generate the catalog, run the following from the directory containing `Package.swift`, using a verified model pack:

```sh
python3 make_model_catalog.py MODEL_DIRECTORY
```

Replace `MODEL_DIRECTORY` with the directory containing `manifest.json`. The command writes `App/ModelCatalog.json`. Preserve the model architecture and weights supported by the inference engine.

## Configuring the app's model source

Before building, set `repository` and `revision` in [App/ModelSource.json](../App/ModelSource.json):

```json
{
  "repository": "owner/reuse-apple",
  "revision": "COMMIT_SHA"
}
```

Replace `repository` with the distribution repository and `COMMIT_SHA` with a commit SHA from that repository. This revision identifies the distributed files and is separate from the original NVIDIA model revision. If `repository` is empty, the app disables downloads.

Each file is fetched from:

```text
https://huggingface.co/<repository>/resolve/<revision>/<file>
```

The app bundles the source settings and catalog, then downloads and stores the model files.

### Trying a private model

The sample app accepts a Hugging Face token through the `REUSE_HF_TOKEN` launch environment variable. Set it in the Xcode scheme's Run settings or pass it through your development tools at launch. Use a token with read access to the repository.

Keep the token out of source files, `ModelSource.json` and app resources. This method does not save the token to device files or carry it over to normal launches. Downloaded models work offline. After deleting a private model, launch with credentials again to download it.

In the SDK, pass the token at runtime through `ReuseModelSource.accessToken`. Omit it for public models.

```swift
let source = try ReuseModelSource(
    huggingFaceRepository: "owner/reuse-apple",
    revision: "COMMIT_SHA",
    accessToken: ProcessInfo.processInfo.environment["REUSE_HF_TOKEN"]
)
```

## Downloading and deleting in the app

Downloads show progress and support cancellation and retry. Completed files are reused after checking their size and SHA-256 hash. Retry operates at the file level; an incomplete file restarts from the beginning. Downloads stop when the app moves to the background.

The model becomes available after all HTTP responses, sizes and SHA-256 hashes have been verified. Before downloading, the app checks for enough space for the remaining files plus a 32 MiB reserve. Core ML compilation caches need additional space.

“モデルを削除” (Delete model) removes all model versions managed by the app, partial downloads and compilation caches. Audio files and measurement results are retained. Downloadable model files are excluded from device backups.

## Integrating with Swift

Load the bundled catalog into `catalogData`. Set `supportURL` and `cachesURL` to your app's Application Support and Caches directory URLs.

```swift
import Foundation
import ReuseKit
import ReuseModelAssets

let catalog = try JSONDecoder().decode(ReuseModelCatalog.self, from: catalogData)
let store = try ReuseModelStore(
    catalog: catalog,
    applicationSupportDirectory: supportURL,
    cachesDirectory: cachesURL
)
let source = try ReuseModelSource(
    huggingFaceRepository: "owner/reuse-apple",
    revision: "COMMIT_SHA"
)

try await store.download(from: source) { progress in
    // progress.fraction ranges from 0...1. Dispatch UI updates to MainActor.
}

let status = try await store.inspect()
if status.isInstalled {
    let engine = ReuseEngine(
        modelPack: ReuseModelPack(root: store.installedModelDirectory),
        cacheDirectory: store.compilationCacheDirectory
    )
    // Run inference with engine.
    await engine.release()
}

// Release the engine and discard references before deleting the model.
try await store.remove()
```

Downloads support `Task` cancellation. Before deletion or a new download, wait for any active inference or download to finish.
