#!/bin/bash
# Root LaunchDaemon (io.maoxor.fanctl): fan curve + macOS energy mode, chosen from the menu bar (SketchyBar "fan").
# Reads the mode the user picked from $MODE_FILE (auto | eco | equilibre | perf | max), every 3 s:
#   auto       macOS decides (fans automatic, energy mode automatic)
#   eco        Low Power Mode, fans automatic
#   equilibre  energy automatic, fans ramp from 50 °C (earlier than Apple, which waits until ~70-80 °C)
#   perf       High Power Mode, fans ramp from 45 °C, never below 40 %
#   max        High Power Mode, fans at full speed
# Control, as Linux fan daemons do it (CoolerControl, thinkfan, fancontrol):
#   - averaged temperature (exponential, ~12 s) so a short turbo spike does not surge the fans;
#   - up at once, down slowly: at most 4 % per step, and only 3 °C under the temperature that set the speed (hysteresis);
#   - emergency: at 95 °C or more, full speed in every manual mode;
#   - the target is rewritten every step: thermalmonitord takes manual fans back, and sleep resets them.
# M5: the mode key is F<n>md (lowercase, no Ftst unlock); Stats' smc tool handles it (checked on this Mac 2026-11-05).
# Fail-safe: on exit, unknown mode or unreadable temperature, the fans go back to automatic.
# Binaries are root-owned copies (Stats' smc, macmon) in /usr/local/libexec/fanctl: never run a user-writable binary as root.
set -u
BIN=/usr/local/libexec/fanctl; SMC="$BIN/smc"; MACMON="$BIN/macmon"
MODE_FILE="${1:?mode file}"; STATUS=/var/run/fanctl.status
read -r -a MIN <<<"$("$SMC" fans 2>/dev/null | awk '/Minimal speed/{printf "%d ", $3}')"
read -r -a MAX <<<"$("$SMC" fans 2>/dev/null | awk '/Maximum speed/{printf "%d ", $3}')"
log() { echo "$(date '+%F %T') $*" >&2; }
fan_auto() { for i in "${!MIN[@]}"; do "$SMC" fan "$i" -m 0 >/dev/null 2>&1; done; }
fan_pct() { # $1 = percent of each fan's range
  for i in "${!MIN[@]}"; do
    "$SMC" fan "$i" -m 1 >/dev/null 2>&1
    "$SMC" fan "$i" -v $(( MIN[i] + (MAX[i]-MIN[i]) * $1 / 100 )) >/dev/null 2>&1
  done
}
energy() { [ "$(pmset -g | awk '/powermode/{print $2}')" = "$1" ] || pmset -a powermode "$1"; }
reading() { "$MACMON" pipe -s 1 -i 300 2>/dev/null | /usr/bin/python3 -c \
  'import json,sys;t=json.loads(sys.stdin.readline())["temp"];print(max(t["cpu_temp_avg"],t["gpu_temp_avg"]))' 2>/dev/null; }
trap 'fan_auto; energy 0; rm -f "$STATUS"; log stop; exit 0' TERM INT
trap 'fan_auto; energy 0' EXIT
log "start: ${#MIN[@]} fans, min ${MIN[*]}, max ${MAX[*]}"
last=""; avg=""; pct=0; set_at=0
while sleep 3; do
  mode=$(head -c 16 "$MODE_FILE" 2>/dev/null | tr -cd 'a-z'); mode=${mode:-auto}
  raw=$(reading)
  if [ -n "$raw" ]; then avg=$(awk -v a="${avg:-$raw}" -v r="$raw" 'BEGIN{printf "%.1f", a + 0.25*(r-a)}'); else avg=""; fi
  # curve: start °C, full °C, floor %
  case "$mode" in auto) c="";; eco) c="";; equilibre) c="50 90 0";; perf) c="45 80 40";; max) c="0 1 100";; *) mode=auto; c="";; esac
  [ "$mode" = "$last" ] || { log "mode $mode"; pct=0; set_at=0; }
  case "$mode" in auto|equilibre) energy 0;; eco) energy 1;; perf|max) energy 2;; esac
  if [ -z "$c" ]; then
    [ "$mode" = "$last" ] || fan_auto
  elif [ -z "$avg" ]; then
    fan_auto; log "no temperature: automatic"
  else
    read -r _ pct set_at <<<"$(awk -v t="$avg" -v raw="$raw" -v c="$c" -v p="$pct" -v s="$set_at" 'BEGIN{
      split(c,k," "); w=(t-k[1])/(k[2]-k[1])*100; if(w<k[3])w=k[3]; if(w>100)w=100;
      if(raw>=95) w=100;                       # emergency, on the raw reading
      if(w>=p){p=w; s=t} else if(t<=s-3){p=(p-w>4)?p-4:w}   # up at once; down 4 %/step once 3 °C under the peak
      printf "%d %d %.1f", p, p, s}')"
    fan_pct "$pct"
  fi
  last=$mode; echo "$mode ${avg:-?} ${pct}" > "$STATUS"
done
