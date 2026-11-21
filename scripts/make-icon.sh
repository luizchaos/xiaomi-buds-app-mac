#!/bin/zsh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift scripts/make-icon.swift "$work/icon_1024.png"

set=$work/AppIcon.iconset
mkdir -p "$set"
for px in 16 32 128 256 512; do
  sips -z $px $px "$work/icon_1024.png" --out "$set/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$work/icon_1024.png" --out "$set/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
cp "$work/icon_1024.png" docs/icon.png
echo "OK: Resources/AppIcon.icns, docs/icon.png"
