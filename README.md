# RE-USE-MLX-CoreML

日本語 | [English](README.en.md)

NVIDIA RE-USEの非公式Apple Silicon向け移植版です。Swiftライブラリとサンプルアプリを使い、MacとiPhoneで同じモデルによるノイズ除去を端末内で実行できます。

モデルは[RE-USE for Apple Silicon (MLX + Core ML)](https://huggingface.co/AILogDev/RE-USE-MLX-CoreML)から取得します。非公開モデルへのアクセス方法は[モデル管理ガイド](docs/MODELS.md#非公開モデルを試す)を参照してください。

## デモ動画

iPhoneでノイズを除去し、再生中に「ノイズあり／ノイズ除去後」を切り替えるデモです。音声をオンにして聴き比べてください。

https://github.com/user-attachments/assets/cecc26f7-bc90-4b8f-83a4-0485c29924ff

## コンポーネント

| コンポーネント | 用途 |
| --- | --- |
| `ReuseKit` | MLX / Core MLによる推論、音声ファイルの読み書き、RTF計測 |
| `ReuseModelAssets` | Hugging Faceからのモデル取得、整合性確認、削除 |
| `ReusePlayback` | 処理前後の音声を同じ位置で切り替える比較再生 |
| RE-USE Lab | iPhone用SwiftUIサンプルアプリ |
| `reuse-probe` | Mac用コマンドラインサンプル |

`Package.swift`のあるディレクトリがパッケージのルートです。`Sources`にSDKとMac CLI、`Tests`にテスト、`App`にiPhoneサンプル、`docs`に利用ガイドを収録しています。

## 動作環境

- Apple Silicon搭載Mac：macOS 15以降。
- iPhone実機：iOS 18以降。
- ビルド確認環境：Xcode 27.2（Swift 6.4.2）、Metal Toolchain、Python 3。
- モデル：約54.2 MB。Core MLのコンパイルキャッシュ用に追加の空き容量が必要です。

MLX Swiftは0.33.0に固定しています。Simulatorは画面確認用で、推論には実機を使います。

## Swift SDKとして使う

Xcodeの「Add Package Dependencies」で`https://github.com/Corvelis/RE-USE-MLX-CoreML.git`のバージョン`0.1.0`を追加し、`ReuseKit`を選びます。[モデル一式](docs/BUILDING.md#macのコマンドラインサンプル)を用意したら、次のように音声ファイルを処理できます。

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

URLの指定、処理モード、モデルの取得と削除は[SDKガイド](docs/SDK.md)を参照してください。

## iPhoneで使う

サンプルアプリの画面表示は日本語です。

アプリのビルド前に[モデル配布先とアクセス方法](docs/MODELS.md)を確認し、[ビルド手順](docs/BUILDING.md)に沿ってインストールします。

1. 「モデルをダウンロード」を押します。取得後はオフラインで処理できます。
2. 「ファイル」から音声を選ぶか、マイクで録音します。どちらも最大5分です。
3. 処理モードを選び、「ノイズを除去」を押します。
4. 結果を再生します。「ノイズあり／ノイズ除去後」で、再生位置を保ったまま切り替えられます。
5. 「WAVを保存」または「共有」で処理後の音声を書き出します。

入力は16 kHz・monoに変換します。出力は16 kHz・mono・Float32 WAVです。「3回でRTFを測る」は準備実行1回と測定3回を行い、結果のJSONを共有できます。アプリがバックグラウンドへ移ると録音・再生・処理・ダウンロードを停止します。

「モデルを削除」はモデル本体、取得途中のファイル、Core MLのコンパイルキャッシュを削除します。録音と処理済みWAV、計測結果は保持します。モデルを再取得すると、再びノイズ除去できます。

## 処理モード

| モード | 実行方法 | 選び方 |
| --- | --- | --- |
| ANE + GPU | CNNをCore ML、Mamba部分をMLX / GPUで実行 | iPhoneアプリの既定のモード |
| MLX GPU | モデル全体をGPUで実行 | GPUだけで処理する場合 |

両モードとも全30段、16個のFP32再帰状態、5秒の処理窓、5％の重なりを保ちます。ANE + GPUはCNNと境界データをFP16で扱うため、MLX GPUと出力に差があります。Core MLの実際の演算配置はOSが決定します。対応するCNN形状がない窓はMLXで処理します。

音声をまとめて処理する方式です。マイク入力をその場で連続変換する用途には、別途ストリーミング処理が必要です。

## 処理速度

RTFは「処理時間 ÷ 音声の長さ」です。0.1なら10秒の音声を約1秒で処理します。

| 端末 | モード | RTF中央値 |
| --- | --- | ---: |
| iPhone 17 Pro / A19 Pro | ANE + GPU・自動選択 | 0.0948 |
| MacBook Air / M2・GPU 8コア | MLX GPU・`foldShared` | 0.1982 |
| MacBook Air / M2・GPU 8コア | ANE + GPU・`foldSeparate` | 0.1469 |

16 kHz・mono・7.92秒の音声、準備実行後の測定です。Macの表は最適化を明示指定した値です。初回準備、入力の長さ、端末の温度などで処理時間は変わります。[測定条件と品質比較](docs/BENCHMARKS.md)を参照してください。

## 開発者向けガイド

- [ビルドとMacサンプルの実行](docs/BUILDING.md)
- [Swift SDKの組み込み](docs/SDK.md)
- [モデルの配布・ダウンロード・削除](docs/MODELS.md)
- [速度と品質の測定結果](docs/BENCHMARKS.md)
- [リリース履歴](CHANGELOG.md)

## ソースパッケージを書き出す

```sh
python3 export_source.py dist/ReuseKit --archive
```

SDK、サンプル、テスト、利用ガイド、ライセンスを含む`dist/ReuseKit`と`dist/ReuseKit.zip`を生成します。書き出したディレクトリをそのままSwift Packageのリポジトリとして使用できます。

## ライセンスと出典

SDK・サンプルアプリのコードと同梱音声は[Apache-2.0](LICENSE)、モデルはOpenMDW-1.1です。[音声の表示](licenses/Audio-Samples.txt)、[配布時の条件](docs/LICENSING.md)、[Third-Party Notices](App/Notices.txt)も確認できます。アプリ内の情報ボタンからも全文を表示します。
