#!/usr/bin/env bash
# Connected when the Wi-Fi interface has an address (the network name would need Location Services).
source "$HOME/.config/sketchybar/colors.sh"
dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/ {getline; print $2}')
if [ -n "$(ipconfig getifaddr "${dev:-en0}" 2>/dev/null)" ]; then
  sketchybar --set "$NAME" icon="󰖩" icon.color="$TEXT"
else
  sketchybar --set "$NAME" icon="󰖪" icon.color="$MUTED"
fi
