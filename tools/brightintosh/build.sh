#!/bin/bash
# Build BrightIntosh from its pinned source and install it in /Applications (tools/brightintosh/README.md).
# The scheme "BrightIntosh" is the free edition: no trial, no purchase (the App Store one is built with STORE).
set -euo pipefail
tag=v6.0.11
commit=f6806b893926d3ed47424396d9f45575713b8709
src="$HOME/src/BrightIntosh"
out="$HOME/Library/Caches/macos-config/brightintosh-build"
[ -d "$src/.git" ] || git clone -q --depth 1 --branch "$tag" https://github.com/niklasr22/BrightIntosh.git "$src"
[ "$(git -C "$src" rev-parse HEAD)" = "$commit" ] || { echo "$src is not $tag ($commit)" >&2; exit 1; }
xcodebuild -quiet -project "$src/BrightIntosh.xcodeproj" -scheme BrightIntosh -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$out" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= build
pgrep -x BrightIntosh >/dev/null && { echo "quit BrightIntosh first" >&2; exit 1; }
rm -rf /Applications/BrightIntosh.app
cp -R "$out/Build/Products/Release/BrightIntosh.app" /Applications/
# It starts boosted by default: stay off until asked for (Cmd+Option+B). Only on a first install.
prefs="$HOME/Library/Group Containers/group.de.brightintosh.app/Library/Preferences"
if [ ! -e "$prefs/group.de.brightintosh.app.plist" ]; then
  mkdir -p "$prefs"
  defaults write "$prefs/group.de.brightintosh.app" active -bool false
fi
echo "installed $(defaults read /Applications/BrightIntosh.app/Contents/Info CFBundleShortVersionString) in /Applications"
