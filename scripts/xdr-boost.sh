#!/bin/bash
# XDR brightness boost (scripts/xdr-boost.swift); Cmd+F3 in Hammerspoon starts and stops it.
exec "$(dirname "$(readlink -f "$0")")/swift-tool.sh" xdr-boost "$@"
