#!/bin/bash
# Runs scripts/<tool>.swift, built on first run and after each change of the source: scripts/swift-tool.sh <tool> [args].
set -euo pipefail
tool="$1"; shift
src="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/$tool.swift"
bin="$HOME/Library/Caches/macos-config/$tool"
if [ ! -x "$bin" ] || [ "$src" -nt "$bin" ]; then
  mkdir -p "$(dirname "$bin")"
  /usr/bin/swiftc -O "$src" -o "$bin.tmp" && mv "$bin.tmp" "$bin"
fi
exec "$bin" "$@"
