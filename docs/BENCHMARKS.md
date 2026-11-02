# 速度と品質

日本語 | [English](BENCHMARKS.en.md)

RTFは処理秒数を入力音声の秒数で割った値です。小さいほど高速です。以下は2026年11月2日の測定値です。

## 測定条件

| 項目 | 条件 |
| --- | --- |
| 入力 | 16 kHz・mono・7.92秒の音声 |
| 測定 | 各設定を1回準備実行後、比較する設定をAB / BA交互に5組実行 |
| 集計 | 5回のRTF中央値と最小〜最大 |
| 含む処理 | STFT、全30段のモデル推論、iSTFT、窓の結合、GPU完了待ち |
| 別途必要な処理 | ファイル読み込み・変換、モデル読み込み、初回コンパイル、保存、再生 |
| モデル | 全30段、16個のFP32再帰状態、5秒窓、5％の重なり、元の時間・周波数解像度 |
| 端末状態 | 低電力モードoff、熱状態nominal。MacはAC接続 |

速度測定の7.92秒音声は[URGENT 2024の`fileid_26119`](https://huggingface.co/datasets/urgent-challenge/urgent2024_official)（CC BY-NC-SA 4.0）、品質測定のペアは[Edinburgh Noisy Speech Database](https://doi.org/10.7488/ds/2117)（CC BY 4.0）です。

同梱の`sample_noisy.wav`は、日本語音声と掃除機のノイズを含む10.8573125秒のオリジナル録音です。対応するクリーン正解音声はありません。以下の7.92秒の測定やclean / noisyペアによる品質測定とは別の入力です。

## iPhone 17 Pro / A19 Pro

iOS 27.2、ANE + GPUモード、最適化は`.recommended`が選ぶ`.naxFullShared16`です。

| 設定 | RTF中央値 | 最小〜最大 | 7.92秒の処理時間 |
| --- | ---: | ---: | ---: |
| `naxFullShared16` | 0.09480 | 0.09257〜0.09809 | 約0.75秒 |

この設定はiOS 26.2以降かつ対応GPUで自動選択します。アプリでは「ANE + GPU」を選びます。

## MacBook Air / M2

GPU 8コア、メモリ24 GiB、macOS 27.2。

| モード・設定 | RTF中央値 | 最小〜最大 | 7.92秒の処理時間 |
| --- | ---: | ---: | ---: |
| MLX GPU・`foldShared` | 0.19824 | 0.19565〜0.19979 | 約1.57秒 |
| ANE + GPU・`foldSeparate` | 0.14692 | 0.14645〜0.14761 | 約1.16秒 |

Macの自動選択は`warpFast`です。同じ比較での`warpFast`のRTF中央値はMLX GPUが0.20935、ANE + GPUが0.15852でした。表の設定には線形層の合成に伴う追加のFP16丸めがあり、利用時に明示指定します。[SDKの設定方法](SDK.md)を参照してください。

## 同梱サンプルでの測定

`sample_noisy.wav`（16 kHz・mono・10.8573125秒）をMacBook Air / M2で処理した結果です。各設定を1回準備実行後、`warpFast`と速度設定をAB / BA交互に5組実行しました。

| モード・設定 | RTF中央値 | 最小〜最大 | `warpFast`のRTF中央値 |
| --- | ---: | ---: | ---: |
| MLX GPU・`foldShared` | 0.19912 | 0.19876〜0.20054 | 0.21130 |
| ANE + GPU・`foldSeparate` | 0.15486 | 0.15461〜0.15591 | 0.16585 |

同じモードの`warpFast`に対する追加相対RMSEは、`foldShared`が0.02333％、`foldSeparate`が0.04757％でした。これは最適化による波形の数値差で、聴感上の劣化率ではありません。

## 品質

全モードでSSMの投影にFP16、再帰状態と正規化にFP32を使用します。ANE + GPUはCNNと境界データもFP16です。`foldShared`、`foldSeparate`、`naxFullShared16`には線形層の合成に伴う追加の丸めがあります。

正解音声のあるclean / noisyペア1組で、各端末のANE + GPUについて`warpFast`と速度設定を比較しました。

| 端末・設定 | `warpFast` STOI | 速度設定 STOI | `warpFast` SI-SDR | 速度設定 SI-SDR |
| --- | ---: | ---: | ---: | ---: |
| A19 Pro・`naxFullShared16` | 0.94836095 | 0.94835503 | 14.993870 dB | 14.994723 dB |
| M2・`foldSeparate` | 0.94833868 | 0.94833576 | 14.993901 dB | 14.993424 dB |

この音声ペアでは両指標の差は小さく、7.92秒の音声での追加相対RMSEはA19 Proが約0.0578％、M2が約0.0571％でした。評価対象はこのペア、7.92秒の音声、無音・インパルス・小音量・短音声の合成入力です。

M2の`foldSeparate`は合成インパルスで相対RMSE 2.24％、最大振幅差0.000977でした。追加の丸めを抑える選択肢として`residualFuse`を指定でき、M2の7.92秒の評価音声では`warpFast`と出力が一致しました。波形RMSEは聴感上の劣化率を表す値ではなく、品質は入力に依存します。

## 利用時の計測

アプリの「3回でRTFを測る」、またはMacの[`reuse-probe`](BUILDING.md)で測定できます。初回準備の時間と、準備後のRTFを分けて評価してください。入力の長さ、温度、電源状態、同時に動くアプリによって値が変わります。短い音声は呼び出しの固定費の割合が大きくなります。

ANE + GPUはCNNにCore MLの`cpuAndNeuralEngine`を指定します。実際の演算配置はCore MLが決定し、CNN形状がモデル一式にない窓はMLXへ切り替えます。
