#!/usr/bin/env bash
# Wi-Fi item. Icon: connected when the Wi-Fi interface has a routable address, IPv4 or IPv6 (an iPhone hotspot is often
# IPv6 + 464XLAT, with no DHCP IPv4: `ipconfig getifaddr` is then empty although the Mac is online).
# Click: a menu like macOS's own: Wi-Fi on/off, networks, login page, settings. Networks: the ones macOS already knows
# from its last scan are shown at once, then a fresh scan replaces them (~3 s). Names come from
# ~/Applications/WifiScan.app (tools/wifi: macOS gives them only to an app allowed Location Services); without that
# permission, the saved networks. A row joins (wifi-connect.sh, which also opens a captive portal's login page).
source "$HOME/.config/sketchybar/colors.sh"
dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/ {getline; print $2}'); dev=${dev:-en0}
P="$HOME/.config/sketchybar/plugins"; CACHE="$HOME/.cache/wifi-menu"
icon() {
  if ifconfig "$dev" 2>/dev/null | grep -q "status: active" &&
     ifconfig "$dev" | awk '/inet /{print $2} /inet6 /{print $2}' | grep -qvE '^(fe80:|169\.254\.)'; then
    sketchybar --set wifi icon="󰖩" icon.color="$TEXT"
  else sketchybar --set wifi icon="󰖪" icon.color="$MUTED"; fi
}
row() { # $1 id, $2 icon, $3 label, $4 click, $5 color
  sketchybar --add item "wifi.net.$1" popup.wifi \
             --set "wifi.net.$1" icon="$2" label="$3" icon.color="${5:-$TEXT}" icon.padding_left=12 label.padding_right=14 \
                   background.height=22 click_script="$4"
}
networks() { # $1 = scan file: rows for its networks
  sketchybar --remove '/wifi\.net\.n.*/' >/dev/null 2>&1
  local n=0 cur ssid rssi secure bars lock
  if [ "$(jq -r '.auth' "$1" 2>/dev/null)" = ok ]; then
    cur=$(jq -r '.current' "$1")
    while IFS=$'\t' read -r ssid rssi secure; do
      bars="󰤟"; [ "$rssi" -gt -75 ] && bars="󰤢"; [ "$rssi" -gt -65 ] && bars="󰤥"; [ "$rssi" -gt -55 ] && bars="󰤨"
      lock=""; [ "$secure" = true ] && lock="  󰌾"
      if [ "$ssid" = "$cur" ]; then row "n$n" "$bars" "$ssid  ✓" "" "$ACCENT"
      else row "n$n" "$bars" "$ssid$lock" "$P/wifi-connect.sh $(printf %q "$ssid")"; fi
      n=$((n+1)); [ $n -ge 12 ] && break
    done < <(jq -r '.current as $c | (.networks | map(select(.ssid == $c)) + map(select(.ssid != $c)))[] | [.ssid, .rssi, .secure] | @tsv' "$1")
  else
    while read -r ssid; do row "n$n" "󰤨" "$ssid" "$P/wifi-connect.sh $(printf %q "$ssid")"; n=$((n+1)); [ $n -ge 10 ] && break
    done < <(networksetup -listpreferredwirelessnetworks "$dev" | tail -n +2 | sed 's/^[[:space:]]*//')
    row n$n "󰋽" "Réseaux enregistrés (autoriser WifiScan : localisation)" "" "$MUTED"
  fi
  fixed
}
fixed() { # login page and settings, re-added so they stay under the networks
  sketchybar --remove wifi.net.portal --remove wifi.net.settings >/dev/null 2>&1
  row portal "󰖟" "Page de connexion du réseau" "$P/wifi-connect.sh --portal"
  row settings "󰒓" "Réglages Wi-Fi" "open 'x-apple.systempreferences:com.apple.wifi-settings-extension'; sketchybar --set wifi popup.drawing=off"
}
case "$SENDER" in
  mouse.exited.global) sketchybar --set wifi popup.drawing=off; exit 0 ;;
  mouse.clicked)
    if [ "$(sketchybar --query wifi | jq -r '.popup.drawing')" = on ]; then sketchybar --set wifi popup.drawing=off; exit 0; fi
    sketchybar --remove '/wifi\.net\..*/' >/dev/null 2>&1
    if [ "$(networksetup -getairportpower "$dev" | awk '{print $NF}')" = On ]; then
      row power "󰖩" "Wi-Fi : activé" "networksetup -setairportpower $dev off; sketchybar --set wifi popup.drawing=off"
      on=1
    else row power "󰖪" "Wi-Fi : désactivé" "networksetup -setairportpower $dev on; sketchybar --set wifi popup.drawing=off" "$MUTED"; on=0; fi
    fixed; sketchybar --set wifi popup.drawing=on
    if [ $on = 1 ]; then
      open -g -W "$HOME/Applications/WifiScan.app" --args --cached 2>/dev/null; networks "$CACHE/scan-cached.json"
      ( open -g -W "$HOME/Applications/WifiScan.app" 2>/dev/null
        [ "$(sketchybar --query wifi | jq -r '.popup.drawing')" = on ] && networks "$CACHE/scan.json" ) &
    fi
    ;;
esac
icon
