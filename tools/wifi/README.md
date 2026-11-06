# WifiScan (Wi-Fi menu of the bar)

macOS 14+ hides Wi-Fi network names (`<redacted>` in system_profiler, ipconfig, networksetup) from any process without
Location Services. `WifiScan.app` is a windowless app that scans with CoreWLAN and writes `~/.cache/wifi-menu/scan.json`
for the SketchyBar Wi-Fi menu (`tools/sketchybar/plugins/wifi.sh`); joining goes through `networksetup`
(`wifi-connect.sh`: saved password, else a macOS password dialog).

- **Build:** `tools/wifi/build.sh` → `~/Applications/WifiScan.app` (ad-hoc signed).
- **Permission (user):** System Settings → Privacy & Security → Location Services: on, and WifiScan allowed.
  Without it the menu lists the saved networks instead of the nearby ones.
