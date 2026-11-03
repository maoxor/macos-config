#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Chercher une fenêtre
# @raycast.mode silent
# Optional parameters:
# @raycast.packageName macos-config
# @raycast.icon 🪟
# @raycast.description Every window of every OmniWM workspace, by title (OmniWM's palette, also Hyper+Space).
exec "$HOME/.local/bin/omniwmctl" command open-command-palette windows
