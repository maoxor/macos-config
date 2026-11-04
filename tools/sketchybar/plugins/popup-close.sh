#!/usr/bin/env bash
# Close an item's popup when the pointer leaves the bar.
[ "$SENDER" = mouse.exited.global ] && sketchybar --set "$NAME" popup.drawing=off
exit 0
