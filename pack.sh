#!/bin/bash
# Build LyricsWidget.app — a double-clickable macOS app bundle.
set -e
cd "$(dirname "$0")"

swift build -c release
[ -f AppIcon.icns ] || swift makeicon.swift
APP="LyricsWidget.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LyricsWidget "$APP/Contents/MacOS/LyricsWidget"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it:      open $APP"
echo "Install it:  mv $APP /Applications/"
