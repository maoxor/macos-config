#!/bin/bash
# Hammerspoon memory guard (docs/bugs.md B20), run every minute by the launchd agent hammerspoon-guard.
# Window captures that agents make through `hs -c` (hs.image:saveToFile) leave ~500 MB each that Hammerspoon frees
# only now and then: it reached 4.8 GB. Above HS_GUARD_MB (1500) and with the user away for HS_GUARD_IDLE seconds
# (120: a restart takes ~0.5 s, shortcuts included), restart it. One line per restart in the agent's log.
set -u
limit_mb=${HS_GUARD_MB:-1500}
idle_min=${HS_GUARD_IDLE:-120}
pid=$(pgrep -x Hammerspoon) || exit 0
mb=$(footprint -p "$pid" 2>/dev/null | awk 'NR==2 {print int($(NF-5) * ($(NF-4) == "GB" ? 1024 : $(NF-4) == "KB" ? 1/1024 : 1))}')
[ "${mb:-0}" -gt "$limit_mb" ] || exit 0
idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF / 1e9); exit}')
[ "${idle:-0}" -ge "$idle_min" ] || exit 0
echo "$(date '+%F %T') Hammerspoon at ${mb} MB, user idle ${idle} s: restart"
"$(dirname "$(readlink -f "$0")")/restart-hammerspoon.sh"
