#!/bin/bash
# LuLu settings (root; run after LuLu's extension is approved). Apple-signed programs and apps installed before LuLu
# are allowed silently; everything new asks. VirusTotal lookups off (no hashes sent out).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
P=/Library/Objective-See/LuLu/preferences.plist
for kv in allowApple:true allowInstalled:true allowDNS:true passiveMode:false noVTMode:true; do
  /usr/libexec/PlistBuddy -c "Delete :${kv%%:*}" "$P" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :${kv%%:*} bool ${kv#*:}" "$P"
done
chmod 644 "$P"
pkill -f com.objective-see.lulu.extension || true      # relaunched by the system with the new settings
echo "OK: LuLu preferences set."
