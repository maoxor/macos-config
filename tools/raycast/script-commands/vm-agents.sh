#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title VM des agents
# @raycast.mode silent
# @raycast.packageName macos-config
# @raycast.icon 🤖
# @raycast.description Ouvrir l'écran de la VM des agents (la démarre si besoin) pour regarder ou reprendre la main
"$HOME/.local/bin/agents-vm" view >/dev/null 2>&1 &
