#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/sample.jpg"

ffmpeg -loglevel error -y \
  -f lavfi -i testsrc2=duration=1:size=640x360:rate=1 \
  -frames:v 1 "$OUT"

echo "Generated $OUT"
