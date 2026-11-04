#!/usr/bin/env bash
# Share of all cores in use (ps, no sampling delay).
n=$(sysctl -n hw.ncpu)
pct=$(ps -A -o %cpu= | awk -v n="$n" '{s += $1} END {printf "%d", s / n}')
sketchybar --set "$NAME" label="${pct}%"
