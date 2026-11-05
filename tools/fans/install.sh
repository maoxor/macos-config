#!/bin/bash
# Install the fan/energy daemon (needs admin: run it yourself with sudo).  sudo tools/fans/install.sh   |  --uninstall
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
U="${SUDO_USER:?run through sudo}"; H=$(dscl . -read /Users/"$U" NFSHomeDirectory | awk '{print $2}')
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN=/usr/local/libexec/fanctl; PL=/Library/LaunchDaemons/io.maoxor.fanctl.plist
launchctl bootout system "$PL" 2>/dev/null || true
if [ "${1:-}" = --uninstall ]; then rm -rf "$BIN" "$PL"; echo "Removed (fans back to automatic)."; exit 0; fi
install -d -o root -g wheel -m 755 "$BIN"
install -o root -g wheel -m 755 /Applications/Stats.app/Contents/Resources/smc "$BIN/smc"
install -o root -g wheel -m 755 "$(readlink -f /opt/homebrew/bin/macmon)" "$BIN/macmon"
install -o root -g wheel -m 755 "$HERE/fanctl-daemon.sh" "$BIN/fanctl-daemon.sh"
sudo -u "$U" mkdir -p "$H/.local/state/fanctl"; [ -f "$H/.local/state/fanctl/mode" ] || echo auto | sudo -u "$U" tee "$H/.local/state/fanctl/mode" >/dev/null
cat > "$PL" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.maoxor.fanctl</string>
  <key>ProgramArguments</key><array><string>$BIN/fanctl-daemon.sh</string><string>$H/.local/state/fanctl/mode</string></array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/fanctl.log</string>
</dict></plist>
P
chmod 644 "$PL"; launchctl bootstrap system "$PL"; echo "Installed: io.maoxor.fanctl (mode file $H/.local/state/fanctl/mode)"
