#!/usr/bin/env bash
# Power button (top left): click opens the popup; a row passes its action as $1.
# Restart and shut down are FORCED (owner's choice, 2026-11-12: Chrome refused to quit and blocked a restart): every
# regular app gets SIGTERM, those still alive after 5 s get SIGKILL (unsaved work is lost), then loginwindow's "really
# restart / shut down" Apple event. No sudo, no synthetic key (see scripts/agents-host-guard.py, 2026-11-05).
force_quit_apps() {   # regular apps of this session (lsappinfo type Foreground), Finder excepted
  local pids alive p
  pids=$(lsappinfo list | awk '/^ *[0-9]+\) "/{sub(/^ *[0-9]+\) "/,""); sub(/".*/,""); n=$0}
    /pid = [0-9]+ .*type="Foreground"/{match($0,/pid = [0-9]+/); if (n != "Finder") print substr($0,RSTART+6,RLENGTH-6)}')
  [ -n "$pids" ] || return 0
  kill -TERM $pids 2>/dev/null
  for _ in 1 2 3 4 5; do
    alive=""; for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && return 0
    sleep 1
  done
  kill -KILL $alive 2>/dev/null
}
case "${1:-}" in
  lock)     sketchybar --set session popup.drawing=off; pmset displaysleepnow ;;   # locks: password required on wake
  sleep)    sketchybar --set session popup.drawing=off; pmset sleepnow ;;
  restart)  sketchybar --set session popup.drawing=off; force_quit_apps; osascript -e 'tell application "loginwindow" to «event aevtrrst»' ;;
  shutdown) sketchybar --set session popup.drawing=off; force_quit_apps; osascript -e 'tell application "loginwindow" to «event aevtrsdn»' ;;
  *) case "$SENDER" in
       mouse.clicked) sketchybar --set "$NAME" popup.drawing=toggle ;;
       mouse.exited.global) sketchybar --set "$NAME" popup.drawing=off ;;
     esac ;;
esac
exit 0
