# Swift SDK

Xcodeの「Add Package Dependencies」からリポジトリURLとバージョンを指定し、必要なproductを追加します。ローカルのパッケージも追加できます。対象はApple Silicon MacとiPhone実機です。[ビルド環境](BUILDING.md)も参照してください。

| Product | 用途 |
| --- | --- |
| `ReuseKit` | 推論、音声ファイルの読み書き |
| `ReuseModelAssets` | モデルのダウンロードと削除 |
| `ReusePlayback` | 処理前後を同じ位置で切り替える比較再生 |

別のSwift PackageからGitHub上の`ReuseKit`を追加する例：

```swift
dependencies: [
    .package(url: "https://github.com/Corvelis/RE-USE-MLX-CoreML.git", branch: "main")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: [
        .product(name: "ReuseKit", package: "re-use-mlx-coreml"),
        .product(name: "ReuseModelAssets", package: "re-use-mlx-coreml"),
        .product(name: "ReusePlayback", package: "re-use-mlx-coreml")
    ])
]
```

ローカルのチェックアウトを使う場合は、パッケージの指定を次のように置き換えます。

```swift
.package(path: "../RE-USE-MLX-CoreML")
```

アプリで使うproductだけを追加してください。

## 音声ファイルを処理する

`inputURL`、`outputURL`、`modelDirectory`、`cacheDirectory`にはアプリが利用するURLを渡します。`modelDirectory`は`manifest.json`のあるディレクトリ、`cacheDirectory`はCore MLのコンパイル結果を保存できるディレクトリです。

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

`ReuseAudioFile.read`はmono / stereoのファイルを16 kHz・monoへ変換します。読み込み上限の既定値は60秒です。配列を直接`enhance`へ渡す場合は、16 kHz・monoの有限な`Float`値を用意します。入力は320サンプル（0.02秒）より長い必要があります。出力は入力と同じサンプル数です。

`ReuseAudioFile.write`は16 kHz・mono・Float32 WAVを保存します。`result.metrics.rtf`がRTF、`processingSeconds`が処理秒数です。計測結果は次のように保存できます。

```swift
try ReuseAudioFile.writeJSON(result.metrics, to: metricsURL)
```

`ReuseEngine`はactorです。アプリ側で推論の開始・キャンセル・削除操作を調整し、同時実行を避けてください。キャンセルには処理を開始した`Task`の`cancel()`を使います。モデルを削除・切り替えする前に処理の終了を待ち、`release()`を呼んでエンジンの参照を破棄します。

## 実行モードと最適化

`mode: .mlx`はモデル全体をGPUで、`.hybrid`はCNNをCore ML、残りをMLX / GPUで処理します。両者の精度と速度は[ベンチマーク](BENCHMARKS.md)を参照してください。

最適化の既定値は`.recommended`です。iOS 26.2以降の対応GPU（`applegpu_g18p`、A19 Proで確認）では`.naxFullShared16`を、それ以外では`.warpFast`を選びます。

| 設定 | 用途・特性 |
| --- | --- |
| `.recommended` | 端末に応じた自動選択 |
| `.warpFast` | Macを含む汎用の既定経路 |
| `.foldShared` | M2でMLX GPUを高速化。線形層の合成に伴う追加のFP16丸めあり |
| `.foldSeparate` | M2でANE + GPUを高速化。同じく追加のFP16丸めあり |
| `.residualFuse` | 線形層を合成せず残差加算を融合。M2の評価音声で`.warpFast`と波形一致 |

明示指定の例：

```swift
let engine = ReuseEngine(
    modelPack: ReuseModelPack(root: modelDirectory),
    cacheDirectory: cacheDirectory,
    optimization: .foldSeparate
)
let result = try await engine.enhance(audio.samples, mode: .hybrid)
```

一度の呼び出しで音声をまとめて処理します。5秒窓と5％の重なりを用いるため、RTFが小さくてもリアルタイムのストリーミングAPIとしては使えません。

## モデルを取得・削除する

モデルの保存先には`ReuseModelAssets`が返す`installedModelDirectory`、コンパイルキャッシュには`compilationCacheDirectory`を渡せます。取得、進捗表示、削除のコードは[モデル管理ガイド](MODELS.md)を参照してください。
