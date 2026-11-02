# リリース履歴

日本語 | [English](CHANGELOG.en.md)

## 0.1.0 — 2026-11-02

Apple Silicon搭載MacとiPhone向けの初版です。

- `ReuseKit`：MLX / Core MLによるノイズ除去、音声ファイルの読み書き、RTF計測。
- `ReuseModelAssets`：Hugging Faceからのモデル取得、サイズ・SHA-256の確認、削除。
- `ReusePlayback`：処理前後の音声を同じ位置で切り替える比較再生。
- iPhoneサンプル「RE-USE Lab」：最大5分の録音・ファイル取り込み、WAV保存・共有、速度計測。初期モードはANE + GPUです。
- Mac用CLI `reuse-probe`：音声ファイルの処理とWAV・計測JSONの出力。
- 日本語・英語の利用ガイド、紹介動画、オリジナルのサンプル録音。

対象はmacOS 15以降のApple Silicon MacとiOS 18以降のiPhone実機です。ビルド確認環境はXcode 27.2（Swift 6.4.2）、Metal Toolchain、Python 3です。モデルは両プラットフォームで共通の約54.2 MBのファイル一式を使い、5秒窓で音声をオフライン処理します。

SDK・サンプルアプリのコードと同梱録音はApache-2.0、モデルはOpenMDW-1.1です。依存ライブラリのライセンスも含め、[ライセンスガイド](docs/LICENSING.md)を参照してください。

[使い方と動作環境](README.md) · [ビルド手順](docs/BUILDING.md) · [速度と品質](docs/BENCHMARKS.md)
