#!/bin/sh
set -eu
cd "$(dirname "$0")"
bundle="${1:?请指定生成的 .app 路径}"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Info.plist "$bundle/Contents/Info.plist"
icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
iconset="$icon_tmp/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
xcrun swiftc -O -target "$(uname -m)-apple-macos14.0" USBTransfer.swift Geometry.swift Capture.swift Serial.swift PixelView.swift main.swift -o "$bundle/Contents/MacOS/NanoKVMPixelWindow"
codesign --force --sign - "$bundle"
