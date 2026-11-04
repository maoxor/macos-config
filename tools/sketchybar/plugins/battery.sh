#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
info=$(pmset -g batt)
pct=$(grep -Eo '[0-9]+%' <<<"$info" | head -1 | tr -d %)
[ -z "$pct" ] && { sketchybar --set "$NAME" drawing=off; exit 0; }
if grep -q "AC Power" <<<"$info"; then icon="󰂄"; color="$OK"
elif [ "$pct" -le 20 ]; then icon="󰂎"; color="$ALERT"
else icon="󰁹"; color="$TEXT"; fi
sketchybar --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="${pct}%"
