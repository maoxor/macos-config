#!/usr/bin/env bash
# Colour the workspace numbers: current = accent and bold, with windows = text, empty = muted.
source "$HOME/.config/sketchybar/colors.sh"
FONT="JetBrainsMono Nerd Font"
"$HOME/.local/bin/omniwmctl" query workspaces --format json 2>/dev/null \
  | jq -r '.result.payload.workspaces[] | select(.number <= 4) | "\(.number) \(.isCurrent) \(.counts.total)"' \
  | while read -r n current total; do
      if [ "$current" = true ]; then
        sketchybar --set "ws.$n" label.color="$ACCENT" label.font="$FONT:ExtraBold:13.0"
      elif [ "${total:-0}" -gt 0 ]; then
        sketchybar --set "ws.$n" label.color="$TEXT" label.font="$FONT:Medium:13.0"
      else
        sketchybar --set "ws.$n" label.color="$MUTED" label.font="$FONT:Medium:13.0"
      fi
    done
