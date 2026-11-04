#!/usr/bin/env bash
# Workspaces 1-4: app icons of their windows (one per app), current workspace on an accent chip (animated).
source "$HOME/.config/sketchybar/colors.sh"
# shellcheck source=/dev/null
source "$(command -v icon_map.sh)"
CTL="$HOME/.local/bin/omniwmctl"
current=$("$CTL" query active-workspace --format json 2>/dev/null | jq -r '.result.payload.workspace.number')
apps=$("$CTL" query windows --format json 2>/dev/null \
  | jq -r '.result.payload.windows[] | select(.isScratchpad | not) | "\(.workspace.number)\t\(.app.name)"' | sort -u)
args=()
for n in 1 2 3 4; do
  icons=""
  while IFS=$'\t' read -r ws app; do
    [ "$ws" = "$n" ] || continue
    __icon_map "$app"; icons+="$icon_result"
  done <<<"$apps"
  if [ "$n" = "$current" ]; then
    args+=(--set "ws.$n" background.color="$ACCENT" icon.color="$ON_ACCENT" label.color="$ON_ACCENT")
  elif [ -n "$icons" ]; then
    args+=(--set "ws.$n" background.color=0x00000000 icon.color="$TEXT" label.color="$TEXT")
  else
    args+=(--set "ws.$n" background.color=0x00000000 icon.color="$MUTED" label.color="$MUTED")
  fi
  args+=(--set "ws.$n" label="$icons" label.drawing="$([ -n "$icons" ] && echo on || echo off)")
done
sketchybar --animate tanh 12 "${args[@]}"
