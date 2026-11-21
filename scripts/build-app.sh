#!/bin/zsh
# Builds build/Redmi Buds.app (release, universal, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/check-localizations.sh

# Universal binary: Apple silicon + Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product RedmiBuds "${ARCHS[@]}"
BIN="$(swift build -c release --show-bin-path "${ARCHS[@]}")/RedmiBuds"
APP="build/Redmi Buds.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/RedmiBuds"

# App icon (regenerate with scripts/make-icon.sh).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Every Resources/Localization/<lang>.lproj becomes a supported language.
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$PLIST"
for dir in Resources/Localization/*.lproj; do
  /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string ${${dir:t}%.lproj}" "$PLIST"
done
codesign --force --sign - "$APP"
echo "OK: $APP"
