#!/usr/bin/env sh
# Release web build for the SRS Review app.
#
# --no-web-resources-cdn is REQUIRED, not a nicety: the default build fetches
# CanvasKit (~1.6-5.7 MB) from fonts.gstatic.com before first paint. Measured
# 2026-09-11 (tool/web_first_paint.py, 4 cold loads per variant against a local
# static server): the CDN build's first paint ranged 1,852-87,216 ms (median
# 18,524 ms); with this flag the engine ships in build/web/canvaskit/ and first
# paint was 1,168-2,688 ms (median 1,288 ms). External requests at boot drop
# from 3 to 1. See docs/uiux/audit-2026-09-11.md §14.
set -eu
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn "$@"
# Guard: a CDN-less build must ship the engine locally.
if [ ! -f build/web/canvaskit/canvaskit.wasm ]; then
  echo "FATAL: build/web/canvaskit/canvaskit.wasm missing - the engine would be fetched from gstatic at runtime" >&2
  exit 1
fi
echo "OK: local CanvasKit present in build/web/canvaskit/"
