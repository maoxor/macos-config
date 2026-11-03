#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Restaurer les sessions
# @raycast.mode silent
# Optional parameters:
# @raycast.packageName macos-config
# @raycast.icon 🔁
# @raycast.needsConfirmation true
# @raycast.description After a crash: reopen Ghostty, Safari, Discord and the Claude Code sessions of the last snapshot (also Cmd+F5 twice).
exec timeout 5 /opt/homebrew/bin/hs -c 'sessionRestore.restore()' </dev/null
