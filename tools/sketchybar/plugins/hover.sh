#!/usr/bin/env bash
# Workspace chips: a faint highlight under the pointer (the current one keeps its accent).
source "$HOME/.config/sketchybar/colors.sh"
current=$("$HOME/.local/bin/omniwmctl" query active-workspace --format json 2>/dev/null | jq -r '.result.payload.workspace.number')
[ "${NAME#ws.}" = "$current" ] && exit 0
case "$SENDER" in
  mouse.entered) sketchybar --animate tanh 8 --set "$NAME" background.color="$HOVER" ;;
  mouse.exited)  sketchybar --animate tanh 8 --set "$NAME" background.color=0x00000000 ;;
esac
