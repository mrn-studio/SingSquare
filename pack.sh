#!/bin/bash
# Build SingSquare.app — a double-clickable macOS app bundle.
set -e
cd "$(dirname "$0")"

swift build -c release
[ -f AppIcon.icns ] || swift makeicon.swift
APP="SingSquare.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SingSquare "$APP/Contents/MacOS/SingSquare"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it:      open $APP"
echo "Install it:  mv $APP /Applications/"
