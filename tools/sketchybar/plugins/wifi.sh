#!/usr/bin/env bash
# Wi-Fi item. Icon: connected when the Wi-Fi interface has an address. Click: a menu like macOS's own, rebuilt each time:
# Wi-Fi on/off, nearby networks (from ~/Applications/WifiScan.app, tools/wifi: macOS gives network names only to an app
# allowed Location Services) or, without that permission, the saved networks; a row connects (wifi-connect.sh).
source "$HOME/.config/sketchybar/colors.sh"
dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/ {getline; print $2}'); dev=${dev:-en0}
icon() {
  if [ -n "$(ipconfig getifaddr "$dev" 2>/dev/null)" ]; then sketchybar --set wifi icon="󰖩" icon.color="$TEXT"
  else sketchybar --set wifi icon="󰖪" icon.color="$MUTED"; fi
}
row() { # $1 id, $2 icon, $3 label, $4 click, $5 color
  sketchybar --add item "wifi.net.$1" popup.wifi \
             --set "wifi.net.$1" icon="$2" label="$3" icon.color="${5:-$TEXT}" icon.padding_left=12 label.padding_right=14 \
                   background.height=22 click_script="$4"
}
case "$SENDER" in
  mouse.exited.global) sketchybar --set wifi popup.drawing=off; exit 0 ;;
  mouse.clicked)
    if [ "$(sketchybar --query wifi | jq -r '.popup.drawing')" = on ]; then sketchybar --set wifi popup.drawing=off; exit 0; fi
    sketchybar --remove '/wifi\.net\..*/' >/dev/null 2>&1
    power=$(networksetup -getairportpower "$dev" | awk '{print $NF}')
    if [ "$power" = On ]; then row power "󰖩" "Wi-Fi : activé" "networksetup -setairportpower $dev off; sketchybar --set wifi popup.drawing=off"
    else row power "󰖪" "Wi-Fi : désactivé" "networksetup -setairportpower $dev on; sketchybar --set wifi popup.drawing=off" "$MUTED"; fi
    row wait "󰑓" "Recherche…" "" "$MUTED"; sketchybar --set wifi popup.drawing=on
    [ "$power" = On ] || { sketchybar --remove wifi.net.wait; exit 0; }
    open -g -W "$HOME/Applications/WifiScan.app" 2>/dev/null
    scan="$HOME/.cache/wifi-menu/scan.json"; sketchybar --remove wifi.net.wait
    C="$HOME/.config/sketchybar/plugins/wifi-connect.sh"; n=0
    if [ "$(jq -r '.auth' "$scan" 2>/dev/null)" = ok ]; then
      cur=$(jq -r '.current' "$scan")
      while IFS=$'\t' read -r ssid rssi secure; do
        bars="󰤟"; [ "$rssi" -gt -75 ] && bars="󰤢"; [ "$rssi" -gt -65 ] && bars="󰤥"; [ "$rssi" -gt -55 ] && bars="󰤨"
        lock=""; [ "$secure" = true ] && lock="  󰌾"
        if [ "$ssid" = "$cur" ]; then row "$n" "$bars" "$ssid  ✓" "" "$ACCENT"
        else row "$n" "$bars" "$ssid$lock" "$C $(printf %q "$ssid")"; fi
        n=$((n+1)); [ $n -ge 12 ] && break
      done < <(jq -r '.networks[] | [.ssid, .rssi, .secure] | @tsv' "$scan")
    else
      while read -r ssid; do row "$n" "󰤨" "$ssid" "$C $(printf %q "$ssid")"; n=$((n+1)); [ $n -ge 10 ] && break
      done < <(networksetup -listpreferredwirelessnetworks "$dev" | tail -n +2 | sed 's/^[[:space:]]*//')
      row hint "󰋽" "Réseaux enregistrés (autoriser WifiScan : localisation)" "" "$MUTED"
    fi
    row settings "󰒓" "Réglages Wi-Fi" "open 'x-apple.systempreferences:com.apple.wifi-settings-extension'; sketchybar --set wifi popup.drawing=off"
    ;;
esac
icon
