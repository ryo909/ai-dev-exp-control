# Day018 YouTube Manual Check

## Current recommendation
- Preferred manual upload file: `/tmp/youtube-current-target-repos/ai-dev-day-018/public/media/demo_youtube_retry_v4.mp4`
- Preferred Pages URL: `https://ryo909.github.io/ai-dev-day-018/media/demo_youtube_retry_v4.mp4`
- Reason: `retry_v4` is materially different from `retry_v3` in duration, scene structure, and audio content.

## retry_v3 reference
- Local file: `/tmp/youtube-current-target-repos/ai-dev-day-018/public/media/demo_youtube_retry_v3.mp4`
- Pages URL: `https://ryo909.github.io/ai-dev-day-018/media/demo_youtube_retry_v3.mp4`
- SHA256: `2f5f21af8632bbbcf791b02cbe02a31289151ed1f01d846d64d62e97e9aa88dc`
- File size: `281003 bytes`
- Duration: `7.0s`
- Resolution: `720x1280`
- Video: `H.264 High`
- Audio: `AAC LC mono 48k`

## retry_v4 candidate
- Local file: `/tmp/youtube-current-target-repos/ai-dev-day-018/public/media/demo_youtube_retry_v4.mp4`
- Pages URL: `https://ryo909.github.io/ai-dev-day-018/media/demo_youtube_retry_v4.mp4`
- SHA256: `30989020bdf9cd56d129d5e0222dd2405b3850a173bc058566d81becdba1fb0f`
- File size: `287094 bytes`
- Duration: `15.0s`
- Resolution: `720x1280`
- Container: `mp4`
- Video: `H.264 High / yuv420p / 30fps / faststart`
- Audio: `AAC LC mono 48k`

## Manual upload checks
1. Upload the local `retry_v4` file to YouTube Studio first.
2. Confirm the upload remains visible as processing or scheduled, and does not switch to `処理を中止しました。この動画は処理されませんでした`.
3. Wait at least several minutes. If it still exists as processing or scheduled, treat that as a positive signal.
4. If local manual upload succeeds but Make upload fails, the likely problem is in the Make/Pages route.
5. If local manual upload also fails, the likely problem is the asset itself, not Make.

## Route recommendation
- Route A: local manual upload is the cleanest isolation path.
- Route B: Pages URL upload is useful only after Route A succeeds, to check whether remote fetch changes behavior.
