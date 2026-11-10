#!/usr/bin/env bash
# Bluetooth item. Icon: on, off or connected (blueutil, Brewfile). Label: the battery of the connected accessories that
# report one (pmset -g accps lists them, e.g. "-Luna Gamepad (id=…)	10%;"), lowest first, in red at 20 % or less.
# Nothing connected: the icon alone. Click: open the Bluetooth settings.
source "$HOME/.config/sketchybar/colors.sh"
if [ "$SENDER" = "mouse.clicked" ]; then
  open "x-apple.systempreferences:com.apple.BluetoothSettings"; exit 0
fi
BU=$(command -v blueutil || echo /opt/homebrew/bin/blueutil)
if [ -x "$BU" ] && [ "$("$BU" --power 2>/dev/null)" = "0" ]; then
  sketchybar --set "$NAME" icon="󰂲" icon.color="$MUTED" label.drawing=off; exit 0
fi
connected=$([ -x "$BU" ] && "$BU" --connected --format json 2>/dev/null | grep -c '"address"' || echo 0)
# Accessory batteries: "-Name (id=…)<TAB>NN%;", skipping the Mac's own battery.
bats=$(pmset -g accps 2>/dev/null | awk -F'\t' '/^ -/ && !/InternalBattery/ {
  name=$1; sub(/^ -/, "", name); sub(/ \(id=.*$/, "", name); if (match($2, /[0-9]+%/)) print substr($2, RSTART, RLENGTH-1) "\t" name }' | sort -n)
if [ -n "$bats" ]; then
  low=$(head -1 <<<"$bats" | cut -f1)
  label=$(cut -f1 <<<"$bats" | sed 's/$/%/' | paste -sd' ' -)
  color="$TEXT"; [ "$low" -le 20 ] && color="$ALERT"
  sketchybar --set "$NAME" icon="󰂱" icon.color="$ACCENT" label="$label" label.color="$color" label.drawing=on
elif [ "${connected:-0}" -gt 0 ]; then
  sketchybar --set "$NAME" icon="󰂱" icon.color="$ACCENT" label.drawing=off
else
  sketchybar --set "$NAME" icon="󰂯" icon.color="$TEXT" label.drawing=off
fi
