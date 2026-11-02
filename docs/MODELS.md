# モデルの配布と管理

MacとiPhoneは同じモデル一式を使用します。MLXの重みとCore MLの`.mlpackage`を配布し、Core MLのコンパイル結果は各端末で生成します。

対応するモデルは[ModelCatalog.json](../App/ModelCatalog.json)で指定しています。38ファイル、合計54,206,689 bytes（約54.2 MB）です。カタログにはファイルごとのサイズとSHA-256が含まれます。

## Hugging Faceへ配置する

ローカルでモデルのサイズとSHA-256を確認し、モデルカード、ライセンス、SDKソースを揃えるには、次のコマンドを使います。

```sh
python3 export_source.py dist/ReuseKit --archive
python3 prepare_model_release.py MODEL_DIRECTORY dist/ModelPack \
  --sdk-archive dist/ReuseKit.zip
```

`MODEL_DIRECTORY`を`manifest.json`のあるモデルディレクトリに置き換えます。生成先の`dist/ModelPack`には配布に使うファイルだけを含めます。このコマンドはローカルファイルを作成します。

Hugging Faceモデルリポジトリへ、次の構成で配置します。`.mlpackage`はフォルダの内容を含めてアップロードしてください。一般配布では公開し、認証なしで取得できる設定にします。

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

モデルカードには用途、入力・出力仕様、元モデル、変換内容、測定条件を記載します。`LICENSE`には[NVIDIAモデルのライセンス全文](../licenses/NVIDIA-RE-USE.txt)を使用し、モデルカードのライセンスは`openmdw-1.1`とします。元モデルはNVIDIA RE-USEのrevision `31f82f2efad1095034492f236e8dac9239ba713b`です。[配布時の条件](LICENSING.md)も参照してください。

配布ファイルはカタログのサイズ・ハッシュと一致させます。カタログを生成する場合は、検証済みのモデル一式を指定して次を実行します。コマンドは`Package.swift`のあるディレクトリで実行します。

```sh
python3 make_model_catalog.py MODEL_DIRECTORY
```

`MODEL_DIRECTORY`を`manifest.json`のあるディレクトリに置き換えます。生成先は`App/ModelCatalog.json`です。推論エンジンが対応するモデル構造と重みを維持してください。

## アプリの配布先を設定する

ビルド前に[App/ModelSource.json](../App/ModelSource.json)の`repository`と`revision`を設定します。

```json
{
  "repository": "owner/reuse-apple",
  "revision": "COMMIT_SHA"
}
```

`repository`を公開先に、`COMMIT_SHA`をその配布リポジトリのコミットSHAに置き換えます。ここで指定するrevisionは配布ファイルの版です。元のNVIDIAモデルのrevisionとは別に指定します。`repository`が空の場合、アプリはダウンロード操作を無効にします。

各ファイルは次のURLから取得します。

```text
https://huggingface.co/<repository>/resolve/<revision>/<file>
```

アプリには配布先とカタログを含め、モデル本体はダウンロードして保存します。

### 非公開モデルを試す

サンプルアプリは、起動時の環境変数`REUSE_HF_TOKEN`からHugging Faceトークンを受け取れます。XcodeのSchemeのRun設定で指定するか、開発ツールから起動時に渡します。対象リポジトリの読み取り権限があるトークンを使用してください。

トークンをソース、`ModelSource.json`、アプリのリソースに含めないでください。この方式ではトークンを端末のファイルに保存せず、通常の起動には引き継ぎません。モデルの取得が済めば、オフラインで推論できます。非公開モデルを削除した後に再取得する場合は、認証情報を渡して起動します。

SDKでは`ReuseModelSource`の`accessToken`に実行時の値を渡します。公開モデルでは省略できます。

```swift
let source = try ReuseModelSource(
    huggingFaceRepository: "owner/reuse-apple",
    revision: "COMMIT_SHA",
    accessToken: ProcessInfo.processInfo.environment["REUSE_HF_TOKEN"]
)
```

## アプリでの取得と削除

ダウンロード中は進捗を表示し、中断・再試行できます。取得済みのファイルはサイズとSHA-256を確認して再利用します。再試行はファイル単位で、途中まで取得した1ファイルをバイト単位で再開する方式ではありません。アプリがバックグラウンドへ移るとダウンロードを中断します。

全ファイルのHTTP応答、サイズ、SHA-256の確認が完了すると、モデルが使用可能になります。取得前には残りのファイルサイズと32 MiBの予備容量を確認します。Core MLのコンパイルキャッシュには別途容量が必要です。

「モデルを削除」は、アプリが管理するモデルの全バージョン、取得途中のファイル、コンパイルキャッシュを削除します。音声ファイルと計測結果は保持します。再取得可能なモデル本体はバックアップ対象から除外します。

## Swiftで組み込む

`catalogData`にはアプリに含めたカタログを読み込みます。`supportURL`と`cachesURL`にはアプリのApplication SupportとCachesのURLを渡します。

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
    // progress.fractionは0...1。UIの更新はMainActorへ渡します。
}

let status = try await store.inspect()
if status.isInstalled {
    let engine = ReuseEngine(
        modelPack: ReuseModelPack(root: store.installedModelDirectory),
        cacheDirectory: store.compilationCacheDirectory
    )
    // engineで推論します。
    await engine.release()
}

// 使用中のエンジンを解放し、参照を破棄してから削除します。
try await store.remove()
```

ダウンロードは`Task`のキャンセルに対応します。削除や再ダウンロードを行う際は、アプリ側で推論・ダウンロードの終了を待ってください。
