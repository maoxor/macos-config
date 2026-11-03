#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fond d'écran suivant
# @raycast.mode silent
# Optional parameters:
# @raycast.packageName macos-config
# @raycast.icon 🖼️
# @raycast.description Next image of ~/Pictures; the theme follows (also F3).
exec timeout 5 /opt/homebrew/bin/hs -c 'wallpaperCycle.next()' </dev/null
