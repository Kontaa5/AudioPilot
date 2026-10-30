#!/bin/bash
# Baut SoundController.app (Release, ad-hoc signiert, Hardened Runtime).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/SoundController.app"
rm -rf "build/SoundController.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SoundController "$APP/Contents/MacOS/SoundController"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements Resources/SoundController.entitlements "$APP"
echo "Fertig: $APP"
