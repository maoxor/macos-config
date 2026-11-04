#!/usr/bin/env bash
# Memory in use = wired + active + compressed pages, as Activity Monitor's "Memory Used" roughly counts it.
used=$(vm_stat | awk -v page="$(pagesize)" '
  /Pages wired down/ {w = $4} /Pages active/ {a = $3} /occupied by compressor/ {c = $5}
  END {gsub(/\./, "", w); gsub(/\./, "", a); gsub(/\./, "", c); printf "%.0f", (w + a + c) * page / 1e9}')
sketchybar --set "$NAME" label="${used} Go"
