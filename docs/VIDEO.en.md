# Video noise reduction

[日本語](VIDEO.md) | English

RE-USE Lab processes a video's audio on your iPhone and saves it with the original picture. Install the app using the [build instructions](BUILDING.en.md) and download the model first.

## Import, process and compare

1. Use “動画” (Video) to select a video from Photos, or “ファイル” (File) to import one from Files.
2. Select “ANE + GPU” or “MLX GPU” and tap “ノイズを除去” (Remove noise).
3. Play the result and switch between “ノイズあり” (Original) and “ノイズ除去後” (Enhanced). The playback position stays the same. Your selection also applies after pausing or seeking.
4. Tap “写真に保存” (Save to Photos), or use “動画を共有” (Share video) to save to Files or share with another app.

Use “WAVを保存” (Save WAV) to export the enhanced audio separately. “3回でRTFを測る” (Measure RTF over three runs) measures noise reduction on the extracted audio. The displayed RTF excludes video import and export time.

## Input and output formats

- Input must be longer than 0.02 seconds and no longer than five minutes. Supported inputs include MOV, MP4 and M4V videos that the iPhone can decode, with mono or stereo audio.
- Output is MOV. The original video stream is preserved without re-encoding, retaining its resolution, orientation and picture quality. The source file is unchanged.
- Enhanced audio is 16 kHz mono Float32 PCM. Stereo input is also saved as mono enhanced audio.
- Output can be larger than videos with compressed audio. Share it with an app that supports MOV and PCM audio.
- Videos without an audio track, or formats unsupported for reading or MOV export, produce an error.

## Photos access and storage

The Photos picker gives the app access only to the video you select. The first “写真に保存” (Save to Photos) operation asks for permission to add to Photos. You can still save to Files through “動画を共有” (Share video) if you decline.

Video and audio processing takes place on the device. Selecting an iCloud video may require downloading it to the iPhone first. A working copy of the selected video is kept in the app's cache; enhanced MOV, WAV and measurement JSON files are saved in the app's documents. Deleting the model retains processed files.

Allow enough free space for a copy of the source and the exported video. Keep the app in the foreground while processing, then save or share the result.
