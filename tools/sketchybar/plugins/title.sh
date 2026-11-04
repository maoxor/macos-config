#!/usr/bin/env bash
# shellcheck disable=SC2154  # icon_result is set by __icon_map, from the sourced icon_map.sh
# Focused window: the app's icon (sketchybar-app-font) and the window title (the app name when it has none).
# shellcheck source=/dev/null
source "$(command -v icon_map.sh)"
IFS=$'\t' read -r app title < <("$HOME/.local/bin/omniwmctl" query focused-window --format json 2>/dev/null \
  | jq -r '.result.payload.window | "\(.app.name // "")\t\(.title // "")"')
[ -z "$app" ] && app="${INFO:-Finder}"
[ -z "$title" ] && title="$app"
__icon_map "$app"
sketchybar --set "$NAME" icon="$icon_result" label="$title"
