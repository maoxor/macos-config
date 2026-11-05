#!/usr/bin/env bash
# The gap after the media pill follows it, so the spacing between pills stays 10 pt when nothing plays.
# Now playing (media-control: macOS restricts MediaRemote, this Homebrew tool goes through its adapter). Hidden when
# nothing plays; a click toggles play/pause.
source "$HOME/.config/sketchybar/colors.sh"
MC=/opt/homebrew/bin/media-control
if [ "$SENDER" = mouse.clicked ]; then "$MC" toggle-play-pause; sleep 0.3; fi
info=$("$MC" get 2>/dev/null)
if [ -z "$info" ] || [ "$info" = null ]; then sketchybar --set "$NAME" drawing=off --set gap.l3 drawing=off; exit 0; fi
title=$(jq -r '.title // empty' <<<"$info"); artist=$(jq -r '.artist // empty' <<<"$info"); playing=$(jq -r '.playing // false' <<<"$info")
[ -z "$title" ] && { sketchybar --set "$NAME" drawing=off --set gap.l3 drawing=off; exit 0; }
label="$title"; [ -n "$artist" ] && label="$artist — $title"
if [ "$playing" = true ]; then icon="󰎈"; color="$ACCENT"; else icon="󰏤"; color="$MUTED"; fi
sketchybar --set "$NAME" drawing=on --set gap.l3 drawing=on icon="$icon" icon.color="$color" label="$label"
