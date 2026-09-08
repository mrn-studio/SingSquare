#!/bin/bash
# Build LyricsWidget.app — a double-clickable macOS app bundle.
set -e
cd "$(dirname "$0")"

swift build -c release
APP="LyricsWidget.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LyricsWidget "$APP/Contents/MacOS/LyricsWidget"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it:      open $APP"
echo "Install it:  mv $APP /Applications/"
