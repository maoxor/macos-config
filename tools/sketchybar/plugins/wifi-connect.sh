#!/usr/bin/env bash
# Join a Wi-Fi network from the bar menu: a saved network joins with its stored password; otherwise a macOS password
# dialog asks for it (never stored by this script). Then, as macOS's own assistant does, probe captive.apple.com: if the
# network intercepts it (hotel, school, "CESI hotspot"), open its login page. `--portal`: only that last step.
# The login sheet often fails to appear when DNS or Private Relay bypass the network's interception: the page is then
# opened in the default browser on a plain-HTTP address the portal can redirect.
dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/ {getline; print $2}'); dev=${dev:-en0}
sketchybar --set wifi popup.drawing=off
portal() {
  for _ in 1 2 3 4 5 6; do   # the address may take a few seconds after joining
    r=$(curl -s -m 4 -o /dev/null -w '%{http_code} %{redirect_url}' http://captive.apple.com/hotspot-detect.html)
    body=$(curl -s -m 4 http://captive.apple.com/hotspot-detect.html)
    case "$body" in *Success*) [ "${1:-}" = force ] || exit 0
                               osascript -e 'display notification "Déjà connecté à Internet : pas de page de connexion." with title "Wi-Fi"'; exit 0 ;; esac
    [ -n "$body" ] || [ "${r%% *}" != 000 ] && break
    sleep 2
  done
  url=$(printf %s "$r" | cut -d' ' -f2); [ -n "$url" ] || url="http://captive.apple.com/hotspot-detect.html"
  open "/System/Library/CoreServices/Captive Network Assistant.app" 2>/dev/null; sleep 2
  pgrep -xq "Captive Network Assistant" || open "$url"
}
if [ "${1:-}" = --portal ]; then portal force; exit 0; fi
ssid="$1"
out=$(networksetup -setairportnetwork "$dev" "$ssid" 2>&1)
if [ -n "$out" ]; then
  pw=$(osascript -e "display dialog \"Mot de passe du réseau « $(printf %s "$ssid" | sed 's/[\\"]/\\&/g') »\" default answer \"\" with hidden answer with title \"Wi-Fi\" buttons {\"Annuler\", \"Se connecter\"} default button 2" \
        -e 'text returned of result' 2>/dev/null) || exit 0
  out=$(networksetup -setairportnetwork "$dev" "$ssid" "$pw" 2>&1); unset pw
  [ -n "$out" ] && { osascript -e "display notification \"$(printf %s "$out" | sed 's/[\\"]/\\&/g')\" with title \"Wi-Fi : échec\""; exit 1; }
fi
sketchybar --trigger wifi_change
portal
