#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/Port Watch.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -parse-as-library -target arm64-apple-macos14 Sources/PortWatch/*.swift -o "$app/Contents/MacOS/PortWatch"
cp Info.plist "$app/Contents/"
codesign --force --sign - "$app"
echo "$app"
