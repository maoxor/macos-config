#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title État du Mac
# @raycast.mode fullOutput
# Optional parameters:
# @raycast.packageName macos-config
# @raycast.icon 🩺
# @raycast.description Memory, CPU and GPU over the last 24 h, the heaviest processes, the memory guard's margin.
repo="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
/usr/bin/python3 "$repo/scripts/perf-journal.py" report 2>&1 | head -24
echo
"$HOME/.local/bin/memory-guard" --check 2>&1 | tail -3
