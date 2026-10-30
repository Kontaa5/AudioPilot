#!/bin/bash
# Baut AudioPilot.app (Release, ad-hoc signiert, Hardened Runtime).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/AudioPilot.app"
rm -rf "build/AudioPilot.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AudioPilot "$APP/Contents/MacOS/AudioPilot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements Resources/AudioPilot.entitlements "$APP"
echo "Fertig: $APP"
