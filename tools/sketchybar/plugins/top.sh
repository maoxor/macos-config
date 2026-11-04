#!/usr/bin/env bash
# Click on CPU: the five busiest processes, then the memory-guard margin; a second click (or leaving) closes it.
source "$HOME/.config/sketchybar/colors.sh"
if [ "$(sketchybar --query cpu | jq -r .popup.drawing)" = on ]; then
  sketchybar --set cpu popup.drawing=off; exit 0
fi
i=0
while read -r pcpu rss comm; do
  name=$(basename "$comm"); name=${name:0:22}
  sketchybar --set "cpu.top.$i" icon="$(printf '%5.1f%%' "$pcpu")" icon.color="$ACCENT" \
             label="$(printf '%-22s %5.1f Go' "$name" "$(awk -v r="$rss" 'BEGIN {print r / 1048576}')")"
  i=$((i + 1))
done < <(ps -Ao pcpu=,rss=,comm= -r | head -5)
guard=$("$HOME/.local/bin/memory-guard" --check 2>/dev/null | head -1)
sketchybar --set cpu.top.5 icon="󰒃" icon.color="$OK" label="${guard:-memory-guard: no answer}" \
           --set cpu.top.6 icon="󰮰" icon.color="$MUTED" label="$(sysctl -n vm.loadavg | tr -d '{}' | awk '{printf "charge %s  %s  %s", $1, $2, $3}')" \
           --set cpu popup.drawing=on
