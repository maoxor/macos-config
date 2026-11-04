#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Onglets Zen
# @raycast.mode silent
# @raycast.packageName macos-config
# @raycast.icon 🔎
# @raycast.description Chercher un onglet ouvert dans Zen et y aller (Hammerspoon, zen-tabs.lua)
timeout 5 hs -c 'zenTabs.show()' </dev/null >/dev/null
