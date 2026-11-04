#!/usr/bin/env bash
# Focused window: an app icon and the window title (the app name when the title is empty).
read -r bundle title < <("$HOME/.local/bin/omniwmctl" query focused-window --format json 2>/dev/null \
  | jq -r '.result.payload.window | "\(.app.bundleId // "") \(.title // .app.name // "")"')
case "$bundle" in
  com.mitchellh.ghostty) icon="" ;;
  app.zen-browser.zen) icon="󰈹" ;;
  com.apple.Safari) icon="󰖟" ;;
  com.hnc.Discord) icon="󰙯" ;;
  net.imput.helium|com.microsoft.VSCode) icon="󰨞" ;;
  *) icon="󰏖" ;;
esac
[ -z "$title" ] && title="${INFO:-Bureau}"
sketchybar --set "$NAME" icon="$icon" label="$title"
