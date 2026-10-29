#!/bin/bash
# Window journal (scripts/window-journal.swift); `window-journal report [hours]` lists the windows that showed over
# the user's work and who opened them.
exec "$(dirname "$(readlink -f "$0")")/swift-tool.sh" window-journal "$@"
