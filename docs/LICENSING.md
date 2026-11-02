# ライセンス

SDKとサンプルアプリのコードは[Apache License 2.0](../LICENSE)で公開します。モデル、依存ライブラリ、音声には、それぞれ次のライセンスが適用されます。

| 対象 | ライセンス | 表示・条件 |
| --- | --- | --- |
| ReuseKit / RE-USE Labのコード | Apache-2.0 | [LICENSE](../LICENSE)と[NOTICE](../NOTICE)を保持 |
| NVIDIA RE-USEのモデル・変換済みモデル | OpenMDW-1.1 | [モデルのライセンス全文](../licenses/NVIDIA-RE-USE.txt)と著作権・出典表示を保持 |
| SpeechLens由来の推論コード | Apache-2.0 | NOTICEに元の著作権表示と改変内容を記載 |
| MLX Swift / MLX / MLX C | MIT | 著作権表示と許諾文を保持 |
| Swift Numerics | Apache-2.0 + Swift Runtime Library Exception | [原文](../licenses/Swift-Numerics.txt)を参照 |
| Metal-cpp | Apache-2.0 | [原文](../licenses/Metal-CPP.txt)を参照 |
| fmt / nlohmann/json | MIT | 許諾文と組み込まれたコードの著作権表示を保持 |
| MLX内部の第三者コード | BSD-2-Clause / BSD-3-Clause / zlib / Apache-2.0など | [第三者表示](../licenses/MLX-Third-Party.txt)を参照 |
| サンプル音声 | CC BY 4.0 | [作者・出典・加工内容](../licenses/Audio-Samples.txt)を保持 |

## アプリやライブラリとして配布する

ソース配布には`LICENSE`、`NOTICE`、`licenses`を含めます。アプリの配布には[App/Notices.txt](../App/Notices.txt)の表示を含め、利用者が閲覧できるようにします。サンプルアプリでは情報ボタンから全文を表示します。

Apache-2.0由来のファイルを変更して配布する場合は、変更したことをファイル内に表示します。MITやBSDなどの第三者コードの条件も保持します。Apache-2.0は、モデルと音声を一括して再許諾するものではありません。

## Hugging Faceでモデルを配布する

モデル用リポジトリの`LICENSE`には、[NVIDIA-RE-USE.txt](../licenses/NVIDIA-RE-USE.txt)の全文を使用します。モデルカードのライセンスは`openmdw-1.1`とし、元モデルの名前・リビジョン、MLX / Core MLへの変換、混合精度化を記載します。

OpenMDW-1.1は商用利用、改変、再配布を許可し、再配布時にライセンスと適用される著作権・出典表示の保持を求めます。モデルの出力には追加条件を課しません。入力音声と生成した音声に関わる権利は、音声自体の条件を確認してください。

## サンプル音声

同梱音声はCassia Valentini-Botinhao / University of EdinburghのNoisy Speech Databaseを16 kHzへ変換したもので、CC BY 4.0です。音声を再配布する場合は作者、出典、ライセンス、加工内容を表示します。この音声からノイズ除去した音声を配布する場合も、元の出典と処理したことを表示してください。

モデルのダウンロード設定は[モデル管理ガイド](MODELS.md)を参照してください。
