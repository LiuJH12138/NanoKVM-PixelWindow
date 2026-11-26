#!/bin/sh
set -eu
cd "$(dirname "$0")"
bundle="${1:?请指定生成的 .app 路径}"
mkdir -p "$bundle/Contents/MacOS"
cp Info.plist "$bundle/Contents/Info.plist"
xcrun swiftc -O -target "$(uname -m)-apple-macos14.0" USBTransfer.swift Geometry.swift Capture.swift Serial.swift PixelView.swift main.swift -o "$bundle/Contents/MacOS/NanoKVMPixelWindow"
codesign --force --sign - "$bundle"
