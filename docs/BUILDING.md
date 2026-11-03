# ビルドとサンプルの実行

日本語 | [English](BUILDING.en.md)

Xcode、Metal Toolchain、Python 3を用意します。ビルド確認環境はXcode 27.2（Swift 6.4.2）です。以下のコマンドは`Package.swift`のあるディレクトリで実行します。

## iPhoneアプリ

1. [モデル配布先とアクセス方法](MODELS.md)を確認します。
2. iPhoneでDeveloper Modeを有効にし、Macへ接続します。
3. 自分のApple Developer Team IDを指定してビルドします。

```sh
zsh build_app.sh iphoneos -allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

`YOUR_TEAM_ID`を自分のTeam IDに置き換えます。依存パッケージはビルド時に取得します。ビルド開始時には2 GiB以上の空きを確認し、依存関係とビルド成果物の容量を確保してください。

生成したXcodeプロジェクトは次のコマンドで開けます。

```sh
open .build/app/ReuseLab.xcodeproj
```

アプリのビルド生成物は`.build/app`に保存します。保存先を変更する場合は`REUSE_BUILD_DIR`を設定し、インストール時にも同じ値を使います。

接続した端末を確認し、名前または識別子を指定してインストールします。

```sh
xcrun devicectl list devices
zsh install_app.sh "DEVICE_NAME_OR_ID"
```

画面だけをSimulatorで確認する場合：

```sh
zsh build_app.sh iphonesimulator CODE_SIGNING_ALLOWED=NO
```

推論と速度計測はiPhone実機で行います。

## Macのコマンドラインサンプル

[Hugging Face CLI](https://huggingface.co/docs/huggingface_hub/en/guides/cli)の`hf`を使う場合、対応するモデル一式を次のように取得できます。

```sh
hf download AILogDev/RE-USE-MLX-CoreML \
  --revision 4b7e50680ba34f10865cab7e24054262596f5ab4 \
  --local-dir ModelPack \
  --include manifest.json model_mlx.safetensors 'hybrid_*.mlpackage/*'
```

非公開モデルには、アクセス権があるアカウントで`hf auth login`してから取得します。別の方法で取得する場合も、`.mlpackage`内のファイルを含む[モデル一式](MODELS.md)を用意します。

MacではSwift 6.4以降のSwift Buildエンジンを使い、MLXのMetalシェーダーと実行ファイルをビルドします。

```sh
xcrun swift build --build-system swiftbuild -c release --product reuse-probe
```

`swift run`にモデルのディレクトリ、入力音声、出力先を渡します。

```sh
xcrun swift run --build-system swiftbuild -c release reuse-probe \
  ModelPack App/Samples/sample_noisy.wav output mlx 3
```

この例は同梱のサンプル音声を処理します。モデルを別の場所に保存した場合は`ModelPack`を`manifest.json`のあるディレクトリに、手持ちの音声を試す場合は`App/Samples/sample_noisy.wav`を入力ファイルに置き換えます。入力は16 kHz・monoへ変換され、最大5分まで読み込めます。引数`3`は準備実行1回の後に3回測定する指定です。出力先には各回のWAVと、RTFなどを含むJSONを保存します。

ANE + GPUで実行する場合は`mlx`を`hybrid`へ変更します。M2向けの速度設定を指定する例：

```sh
xcrun swift run --build-system swiftbuild -c release reuse-probe \
  MODEL_DIRECTORY input.wav output-hybrid hybrid 3 foldSeparate
```

最適化の選び方と精度差は[SDKガイド](SDK.md)、測定条件は[ベンチマーク](BENCHMARKS.md)を参照してください。

## Metal Toolchain

XcodeでMetal Toolchainの追加を求められた場合は、次のコマンドでインストールできます。

```sh
xcodebuild -downloadComponent MetalToolchain
```

## テスト

MacでSDKと比較再生のテストを実行します。GPUを使うテストにはApple Silicon Macが必要です。

```sh
xcrun swift test --build-system swiftbuild -c release -j 4
```

実際のチェックポイントを使うテストは`REUSE_MODEL_PACK`にモデルのディレクトリを指定して実行します。モデル管理だけをテストする場合は次のコマンドも使えます。

```sh
python3 test_model_assets.py
```

同梱サンプルの内容とメタデータを確認する場合：

```sh
python3 verify_sample.py
```

動画の読み込み・保存を確認する場合は、MacにFFmpegも用意して実行します。テストは短い映像と音を生成し、音声の位置・音量、映像と向きの保持、比較用プレイヤー、キャンセル、作業用コピーの削除を確認します。

```sh
python3 test_video_media.py
```

GitHub Actionsでは、モデル管理、動画の読み込み・保存、同梱サンプルの整合性、ライセンス通知、補助スクリプトとXcodeプロジェクトの生成を検証します。
