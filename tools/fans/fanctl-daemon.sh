#!/bin/bash
# Root LaunchDaemon (io.maoxor.fanctl): fan curve + macOS energy mode, chosen from the menu bar (SketchyBar "fan").
# Reads the mode the user picked from $MODE_FILE (auto | eco | equilibre | perf | max), every 3 s:
#   auto       macOS decides (fans automatic, energy mode automatic)
#   eco        Low Power Mode, fans automatic
#   equilibre  energy automatic, fans ramp from 50 °C (earlier than Apple, which waits until ~70-80 °C)
#   perf       High Power Mode, fans ramp from 45 °C, never below 40 %
#   max        High Power Mode, fans at full speed
# Fail-safe: on exit, unknown mode or unreadable temperature, the fans go back to automatic.
# Binaries are root-owned copies (Stats' smc, macmon) in /usr/local/libexec/fanctl: never run a user-writable binary as root.
set -u
BIN=/usr/local/libexec/fanctl; SMC="$BIN/smc"; MACMON="$BIN/macmon"
MODE_FILE="${1:?mode file}"; STATUS=/var/run/fanctl.status
fans=$("$SMC" fans 2>/dev/null | awk '/^Number of fans/{print int($4)}'); fans=${fans:-0}
fan_auto() { for ((i=0;i<fans;i++)); do "$SMC" fan $i -m 0 >/dev/null 2>&1; done; }
fan_set() { # $1 = fraction 0..100 of each fan's range
  "$SMC" fans 2>/dev/null | awk -v p="$1" '/Minimal speed/{mn=$3} /Maximum speed/{print int(mn+(($3-mn)*p/100))}' |
    { i=0; while read -r rpm; do "$SMC" fan $i -m 1 >/dev/null 2>&1; "$SMC" fan $i -v "$rpm" >/dev/null 2>&1; i=$((i+1)); done; }
}
curve() { # $1 temp, $2 start °C, $3 full °C, $4 floor %
  awk -v t="$1" -v a="$2" -v b="$3" -v f="$4" 'BEGIN{p=(t-a)/(b-a)*100; if(p<f)p=f; if(p>100)p=100; print int(p)}'
}
energy() { [ "$(pmset -g | awk '/powermode/{print $2}')" = "$1" ] || pmset -a powermode "$1"; }
trap 'fan_auto; energy 0; rm -f "$STATUS"; exit 0' TERM INT EXIT
last=""
while sleep 3; do
  mode=$(head -c 16 "$MODE_FILE" 2>/dev/null | tr -cd 'a-z'); mode=${mode:-auto}
  temp=$("$MACMON" pipe -s 1 -i 300 2>/dev/null | /usr/bin/python3 -c 'import json,sys;t=json.loads(sys.stdin.readline())["temp"];print(int(max(t["cpu_temp_avg"],t["gpu_temp_avg"])))' 2>/dev/null)
  case "$mode" in
    auto)      energy 0; [ "$last" = auto ] || fan_auto ;;
    eco)       energy 1; [ "$last" = eco ] || fan_auto ;;
    equilibre) energy 0; if [ -n "$temp" ]; then fan_set "$(curve "$temp" 50 90 0)"; else fan_auto; fi ;;
    perf)      energy 2; if [ -n "$temp" ]; then fan_set "$(curve "$temp" 45 80 40)"; else fan_auto; fi ;;
    max)       energy 2; fan_set 100 ;;
    *)         mode=auto; energy 0; fan_auto ;;
  esac
  last=$mode; echo "$mode ${temp:-?}" > "$STATUS"
done
