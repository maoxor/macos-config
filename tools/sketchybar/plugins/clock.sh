#!/usr/bin/env bash
case "$SENDER" in mouse.exited.global) sketchybar --set clock popup.drawing=off; exit 0 ;; esac
sketchybar --set "$NAME" label="$(LC_ALL=fr_FR.UTF-8 date '+%a %-d %b · %H:%M')"
