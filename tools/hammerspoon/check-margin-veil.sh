#!/bin/bash
# Non-regression check for the right-margin black strip (2026-10-15, read-only).
# The margin veil must: be loaded and shown, use a wallpaper file that EXISTS (a deleted source
# file made it draw its dark fallback fill = the black strip), swallow clicks (a click-through
# veil let clicks reach a parked inactive-workspace window = surprise workspace switch), cover the
# right screen edge below OmniWM's overlays, and still receive OmniWM updates
# (ws-hide.lua loaded). --cycle also switches W1/W2/W3 quickly and requires the veil on each.
# Exit 0 = ok ; 1 = regression.
out="$(timeout 8 hs -c '
local v = marginVeil
if not v or not v.canvas then return "FAIL veil not loaded" end
local r = {}
if not (v.path and hs.fs.attributes(v.path)) then r[#r+1] = "FAIL wallpaper file missing: " .. tostring(v.path) end
local down, up = v.canvas:canvasMouseEvents()
if not (down and up) then r[#r+1] = "FAIL veil is click-through" end
local f, full = v.canvas:frame(), hs.screen.mainScreen():fullFrame()
if math.abs((f.x + f.w) - (full.x + full.w)) > 0.5 then r[#r+1] = "FAIL veil does not reach the right edge" end
if v.canvas:level() >= hs.canvas.windowLevels.status then r[#r+1] = "FAIL veil above OmniWM overlays (paints over swipe previews / Niri columns)" end
if not wsHide then r[#r+1] = "FAIL ws-hide.lua not loaded (veil gets no OmniWM updates)" end
if v.suppressed == false and not v.canvas:isShowing() then r[#r+1] = "FAIL veil hidden while nothing intrudes" end
return #r == 0 and "ok" or table.concat(r, "\n")' 2>&1 | grep -v '^-- Loading extension')"
echo "$out"; [ "$out" = "ok" ] || exit 1
if [ "${1:-}" = --cycle ]; then
  C=/Applications/OmniWM.app/Contents/MacOS/omniwmctl
  for n in 2 1 3 1 2 1 3 1; do timeout 5 $C command switch-workspace $n >/dev/null; sleep 0.15; done
  for n in 1 2 3 1; do
    timeout 5 $C command switch-workspace $n >/dev/null; sleep 1
    [ "$(timeout 8 hs -c 'return tostring(marginVeil.canvas:isShowing())')" = true ] || { echo "FAIL veil hidden on workspace $n"; exit 1; }
  done
  echo "ok cycle"
fi
exit 0
