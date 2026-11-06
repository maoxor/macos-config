#!/usr/bin/env bash
# Join a Wi-Fi network from the bar menu: a saved network joins with its stored password; otherwise macOS asks for it in
# a password dialog (never stored by this script).
ssid="$1"; dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/ {getline; print $2}'); dev=${dev:-en0}
sketchybar --set wifi popup.drawing=off
out=$(networksetup -setairportnetwork "$dev" "$ssid" 2>&1)
if [ -n "$out" ]; then
  pw=$(osascript -e "display dialog \"Mot de passe du réseau « $(printf %s "$ssid" | sed 's/[\\"]/\\&/g') »\" default answer \"\" with hidden answer with title \"Wi-Fi\" buttons {\"Annuler\", \"Se connecter\"} default button 2" \
        -e 'text returned of result' 2>/dev/null) || exit 0
  out=$(networksetup -setairportnetwork "$dev" "$ssid" "$pw" 2>&1); unset pw
  [ -n "$out" ] && osascript -e "display notification \"$(printf %s "$out" | sed 's/[\\"]/\\&/g')\" with title \"Wi-Fi : échec\""
fi
sketchybar --trigger wifi_change
