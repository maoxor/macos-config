#!/usr/bin/env bash
# Whole-Mac power draw and CPU temperature from macmon (Apple Silicon sensors, no sudo); temperature turns red from 85 °C.
source "$HOME/.config/sketchybar/colors.sh"
read -r watts temp < <(/opt/homebrew/bin/macmon pipe -s 1 -i 400 2>/dev/null \
  | jq -r '"\(.sys_power // .all_power | floor) \(.temp.cpu_temp_avg | floor)"')
[ -z "$watts" ] && exit 0
color="$TEXT"; [ "${temp:-0}" -ge 85 ] && color="$ALERT"
sketchybar --set "$NAME" label="${watts} W · ${temp}°" label.color="$color"
