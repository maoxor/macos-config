#!/usr/bin/env bash
# $INFO is the new volume on volume_change; otherwise ask macOS.
vol=${INFO:-$(osascript -e 'output volume of (get volume settings)')}
muted=$(osascript -e 'output muted of (get volume settings)')
if [ "$muted" = true ] || [ "${vol:-0}" -eq 0 ]; then icon="󰖁"
elif [ "$vol" -lt 40 ]; then icon="󰕿"
else icon="󰕾"; fi
label="${vol}%"; [ "$muted" = true ] && label="muet"
sketchybar --set "$NAME" icon="$icon" label="$label"
