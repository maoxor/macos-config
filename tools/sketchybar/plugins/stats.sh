#!/usr/bin/env bash
# Every 2 s: CPU share (graph + %), GPU use, memory in use, network down/up. One process for all four.
source "$HOME/.config/sketchybar/colors.sh"
n=$(sysctl -n hw.ncpu)
cpu=$(ps -A -o %cpu= | awk -v n="$n" '{s += $1} END {v = s / n; if (v > 100) v = 100; printf "%d", v}')
gpu=$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | cut -d= -f2)
mem=$(vm_stat | awk -v page="$(pagesize)" '
  /Pages wired down/ {w = $4} /Pages active/ {a = $3} /occupied by compressor/ {c = $5}
  END {gsub(/\./, "", w); gsub(/\./, "", a); gsub(/\./, "", c); printf "%.0f", (w + a + c) * page / 1e9}')
# Network: bytes on the default route's interface since the last sample.
dev=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
read -r rx tx < <(netstat -ibn | awk -v d="${dev:-en0}" '$1 == d && $3 ~ /Link/ {print $7, $10; exit}')
state="${TMPDIR:-/tmp}/sketchybar-net"
now=$(date +%s)
read -r prx ptx pt < "$state" 2>/dev/null
echo "$rx $tx $now" > "$state"
human() { awk -v b="$1" 'BEGIN { if (b < 1024) printf "%d o", b; else if (b < 1048576) printf "%.0f Ko", b / 1024; else printf "%.1f Mo", b / 1048576 }'; }
if [ -n "$prx" ] && [ "$now" -gt "${pt:-0}" ]; then
  dt=$((now - pt)); down=$(( (rx - prx) / dt )); up=$(( (tx - ptx) / dt ))
  [ "$down" -lt 0 ] && down=0; [ "$up" -lt 0 ] && up=0
  net="$(human "$down")/s ↑ $(human "$up")/s"
else
  net="…"
fi
color="$TEXT"; [ "$cpu" -ge 70 ] && color="$ALERT"
sketchybar --push cpu.graph "$(awk -v c="$cpu" 'BEGIN {printf "%.2f", c / 100}')" \
           --set cpu label="${cpu}%" label.color="$color" \
           --set gpu label="${gpu:-0}%" \
           --set mem label="${mem} Go" \
           --set net label="$net"
