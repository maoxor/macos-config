#!/bin/bash
# Build ~/Applications/WifiScan.app (ad-hoc signed; Location permission is asked once, on first run).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; APP="$HOME/Applications/WifiScan.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$HERE/WifiScan.swift" -o "$APP/Contents/MacOS/WifiScan"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.maoxor.wifiscan</string>
  <key>CFBundleName</key><string>WifiScan</string>
  <key>CFBundleExecutable</key><string>WifiScan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationUsageDescription</key><string>macOS ne donne le nom des réseaux Wi-Fi qu'aux apps autorisées à la localisation (menu Wi-Fi de la barre).</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>macOS ne donne le nom des réseaux Wi-Fi qu'aux apps autorisées à la localisation (menu Wi-Fi de la barre).</string>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP"
