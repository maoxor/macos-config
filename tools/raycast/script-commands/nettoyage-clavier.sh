#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Nettoyer le clavier
# @raycast.mode silent
# Optional parameters:
# @raycast.packageName macos-config
# @raycast.icon 🧽
# @raycast.description Blocks every key until a click on the card or 2 minutes (also F4).
exec timeout 5 /opt/homebrew/bin/hs -c 'keyboardClean.start()' </dev/null
