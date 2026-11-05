#!/usr/bin/env bash
# VPN on = the default route goes through a tunnel (utun, ipsec, ppp, wg). Hidden otherwise.
source "$HOME/.config/sketchybar/colors.sh"
dev=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
case "$dev" in
  utun*|ipsec*|ppp*|wg*) sketchybar --set "$NAME" drawing=on icon.color="$OK" label="VPN" ;;
  *) sketchybar --set "$NAME" drawing=off ;;
esac
