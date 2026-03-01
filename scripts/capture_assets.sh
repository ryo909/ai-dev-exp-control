#!/usr/bin/env bash
set -euo pipefail

WORK_DIR=${1:?"Usage: capture_assets.sh <work_dir>"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CAPTURE_JS="$CONTROL_DIR/tools/capture/capture.mjs"

command -v node >/dev/null 2>&1 || { echo "⚠ capture: node not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "⚠ capture: python3 not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "⚠ capture: jq not found"; exit 1; }
[ -f "$CAPTURE_JS" ] || { echo "⚠ capture: $CAPTURE_JS not found"; exit 1; }

SITE_DIR="$WORK_DIR/dist"
[ -d "$SITE_DIR" ] || SITE_DIR="$WORK_DIR"

PORT=$((18000 + (RANDOM % 2000)))
URL="http://127.0.0.1:${PORT}/"

TMP_DIR="$WORK_DIR/.capture_tmp"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

PID=""
cleanup() {
  if [ -n "${PID:-}" ]; then
    kill "$PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SITE_DIR" >/dev/null 2>&1 &
PID=$!
sleep 1

if ! CAP_JSON="$(node "$CAPTURE_JS" --url "$URL" --out "$TMP_DIR" --duration 8 --width 720 --height 1280 2>/dev/null)"; then
  echo "⚠ capture: playwright execution failed"
  exit 1
fi
echo "$CAP_JSON" | jq -e '.ok == true' >/dev/null || {
  echo "⚠ capture: unexpected capture result"
  exit 1
}

FFMPEG_BIN=""
if command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG_BIN="$(command -v ffmpeg)"
else
  FFMPEG_BIN="$(find "$HOME/.cache/ms-playwright" -maxdepth 2 -type f -path '*/ffmpeg-*/ffmpeg-linux' 2>/dev/null | head -n 1 || true)"
fi

if [ -n "$FFMPEG_BIN" ]; then
  "$FFMPEG_BIN" -y -i "$TMP_DIR/demo.webm" -an -c:v libx264 -pix_fmt yuv420p \
    -movflags +faststart "$TMP_DIR/demo.mp4" >/dev/null 2>&1 || true
fi

MEDIA_DIR="$WORK_DIR/public/media"
mkdir -p "$MEDIA_DIR"
cp "$TMP_DIR/cover.png" "$MEDIA_DIR/cover.png"

if [ -f "$TMP_DIR/demo.mp4" ]; then
  cp "$TMP_DIR/demo.mp4" "$MEDIA_DIR/demo.mp4"
  rm -f "$MEDIA_DIR/demo.webm"
elif [ -f "$TMP_DIR/demo.webm" ]; then
  cp "$TMP_DIR/demo.webm" "$MEDIA_DIR/demo.webm"
  rm -f "$MEDIA_DIR/demo.mp4"
else
  echo "⚠ capture: demo video not found"
  exit 1
fi

echo "✅ capture: saved to $MEDIA_DIR"
