#!/usr/bin/env bash
# Fan item: mode picked in the popup (written to ~/.local/state/fanctl/mode, applied by the root daemon io.maoxor.fanctl,
# tools/fans) and the fastest fan's speed. Click: popup with the modes; a popup row passes its mode as $1.
source "$HOME/.config/sketchybar/colors.sh"
F="$HOME/.local/state/fanctl/mode"
if [ -n "${1:-}" ]; then
  mkdir -p "${F%/*}"; echo "$1" > "$F"; sketchybar --set fan popup.drawing=off
elif [ "$SENDER" = mouse.clicked ]; then sketchybar --set fan popup.drawing=toggle; exit 0
elif [ "$SENDER" = mouse.exited.global ]; then sketchybar --set fan popup.drawing=off; exit 0; fi
mode=$(cat "$F" 2>/dev/null || echo auto)
rpm=$(/Applications/Stats.app/Contents/Resources/smc fans 2>/dev/null | awk '/Actual speed/{v=int($3); if(v>m)m=v} END{print m+0}')
case "$mode" in eco) name="Éco";; equilibre) name="Équilibré";; perf) name="Perf";; max) name="Max";; *) name="Auto";; esac
color="$TEXT"; launchctl print system/io.maoxor.fanctl >/dev/null 2>&1 || { [ "$mode" = auto ] || { name="$name ?"; color="$ALERT"; }; }
sketchybar --set fan label="$name · $rpm" label.color="$color"
for m in auto eco equilibre perf max; do
  sketchybar --set "fan.mode.$m" icon="$([ "$m" = "$mode" ] && echo "●" || echo "○")"
done
