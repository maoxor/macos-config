#!/bin/bash
# Window journal (scripts/window-journal.swift): built on first run and after each change of the source, then run.
# `window-journal report [hours]` lists the windows that showed over the user's work and who opened them.
set -euo pipefail
src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/window-journal.swift"
bin="$HOME/Library/Caches/macos-config/window-journal"
if [ ! -x "$bin" ] || [ "$src" -nt "$bin" ]; then
  mkdir -p "$(dirname "$bin")"
  /usr/bin/swiftc -O "$src" -o "$bin.tmp" && mv "$bin.tmp" "$bin"
fi
exec "$bin" "$@"
