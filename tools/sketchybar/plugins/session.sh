#!/usr/bin/env bash
# Power button (top left): click opens the popup; a row passes its action as $1.
# Restart and shut down go through loginwindow's own Apple events: macOS shows its confirmation (with a 60 s countdown)
# and lets apps save, as the Apple menu does. Never a synthetic key (see scripts/agents-host-guard.py, 2026-11-05).
case "${1:-}" in
  lock)     sketchybar --set session popup.drawing=off; pmset displaysleepnow ;;   # locks: password required on wake
  sleep)    sketchybar --set session popup.drawing=off; pmset sleepnow ;;
  restart)  sketchybar --set session popup.drawing=off; osascript -e 'tell application "loginwindow" to «event aevtrrst»' ;;
  shutdown) sketchybar --set session popup.drawing=off; osascript -e 'tell application "loginwindow" to «event aevtrsdn»' ;;
  *) case "$SENDER" in
       mouse.clicked) sketchybar --set "$NAME" popup.drawing=toggle ;;
       mouse.exited.global) sketchybar --set "$NAME" popup.drawing=off ;;
     esac ;;
esac
exit 0
