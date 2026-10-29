#!/bin/bash
# Playwright test browsers (Claude Code experiments) are born in the bottom-right corner instead of over the
# user's windows: OmniWM then parks them on workspace 4 (rules + patch 0029), and the white page they show for
# a frame or two at launch no longer flashes in the middle of the screen. Wraps the "Google Chrome for Testing"
# executable of every ~/Library/Caches/ms-playwright/chromium-* (the real one is kept as "<name>.real").
# Idempotent; run by the launchd agent playwright-offscreen when Playwright installs a new browser.
# Undo: scripts/playwright-offscreen.sh --undo
shopt -s nullglob
for app in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac*/*.app; do
  bin="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
  if [ "${1:-}" = --undo ]; then [ -f "$bin.real" ] && mv -f "$bin.real" "$bin" && echo "restored $bin"; continue; fi
  [ -f "$bin.real" ] || { file "$bin" | grep -q Mach-O || continue; mv "$bin" "$bin.real"; }
  printf '#!/bin/sh\n# macos-config scripts/playwright-offscreen.sh: born in a corner, not over the user'"'"'s windows.\nexec "$0.real" --window-position=2060,1330 "$@"\n' > "$bin"
  chmod +x "$bin"; echo "wrapped $bin"
done
