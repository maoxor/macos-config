#!/bin/bash
# Clears the macOS "… can run in the background" notices (Background Task Management) that stay on screen
# (2026-11-14). The project agents register launchd items; every (re)registration posts one of these notices, and
# macOS 27 keeps it until it is closed by hand. There is no setting to turn them off (only `sfltool resetbtm`, which
# also forgets every Login Items choice). Run by launchd whenever ~/Library/LaunchAgents changes: wait for the
# notice to appear, then restart NotificationCenter, which removes the banners from the screen (they stay listed in
# Notification Center). Side effect: any other banner on screen at that moment also leaves the screen.
set -u
for wait in 6 20; do
  sleep "$wait"
  /usr/bin/killall NotificationCenter 2>/dev/null || true
done
