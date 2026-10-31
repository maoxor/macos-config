#!/bin/bash
# Restart Hammerspoon and wait until its config is loaded (AGENTS.md: restart rather than hs.reload()).
# `open` right after the process is gone can still fail with -600 while LaunchServices finishes the quit: that left
# Hammerspoon down (no shortcuts) for ~2 min on 2026-10-29. So: retry the launch until the IPC answers.
# Extra arguments go to `open` (e.g. --env MallocStackLogging=lite to attribute memory, docs/bugs.md B20).
set -u
# launchd agents (hammerspoon-guard) run with a minimal PATH: hs and timeout come from Homebrew / Nix.
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nix-profile/bin:$PATH"
osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1
for _ in $(seq 1 50); do pgrep -x Hammerspoon >/dev/null || break; sleep 0.2; done
pgrep -x Hammerspoon >/dev/null && pkill -x Hammerspoon
for _ in $(seq 1 20); do
  pgrep -x Hammerspoon >/dev/null || open -g -a Hammerspoon "$@" 2>/dev/null
  for _ in $(seq 1 10); do
    if timeout 2 hs -c 'return wsHide and "up" or "loading"' </dev/null 2>/dev/null | grep -q up; then
      echo "Hammerspoon up: $(timeout 2 hs -c 'return startupTimes[#startupTimes]' </dev/null 2>/dev/null)"
      exit 0
    fi
    sleep 0.3
  done
done
echo "Hammerspoon did not come back: open -a Hammerspoon" >&2
exit 1
