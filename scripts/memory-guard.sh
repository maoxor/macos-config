#!/bin/bash
# Memory guard (scripts/memory-guard.swift): `memory-guard --check` shows what it reads and what it would stop.
exec "$(dirname "$(readlink -f "$0")")/swift-tool.sh" memory-guard "$@"
