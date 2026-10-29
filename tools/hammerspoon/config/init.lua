-- CLI « hs » pour diagnostics et tests (scripts/verify, agents).
require("hs.ipc")
-- Load time of each module in the console ("hs -c 'return startupTimes'"): while init runs, no shortcut
-- works and a key falls through to macOS (bare F4 opened Spotlight during a reload, 2026-10-29).
local t0, last = hs.timer.absoluteTime(), hs.timer.absoluteTime()
startupTimes = {}
local function timed(name)
  local m = require(name)
  local now = hs.timer.absoluteTime()
  startupTimes[#startupTimes + 1] = string.format("%s %.0f ms", name, (now - last) / 1e6)
  last = now
  return m
end
-- Keyboard shortcuts first: they work within milliseconds of a reload, before the slower modules below.
-- Cmd+F1 / Cmd+F2 paste a fixed prompt at the cursor (clipboard restored).
promptInsert = timed("prompt-insert")
-- Under lock-down, Mission Control / Spotlight on F3/F4 with a modifier do nothing.
functionKeys = timed("function-keys")
-- F3: next wallpaper of ~/Pictures (the theme follows).
wallpaperCycle = timed("wallpaper-cycle")
-- F4: cleaning mode, keyboard locked until a click on the banner (or 2 min).
keyboardClean = timed("keyboard-clean")
-- Cmd+F5: reopen apps and Claude Code sessions after a crash.
sessionRestore = timed("session-restore")
-- Safari: Cmd+Left/Right = previous/next tab (outside text fields).
safariTabs = timed("safari-tabs")
-- App shortcuts (Cmd+E = Finder).
poweruserApps = timed("poweruser-apps")
-- Power-user contexts (Ctrl+Alt+Cmd+P).
poweruser = timed("poweruser")
-- Restarts OmniWM and Neru when an Accessibility setting changes (prevents a system-wide freeze).
axGuard = timed("ax-guard")
-- Playwright browsers (workspace 4 by OmniWM rule) never pull the user off their workspace.
testBrowsers = timed("test-browsers")
-- Hide apps with no window on the active OmniWM workspace (no parked-window strip in the right margin).
-- Click-through wallpaper strip over the right gap (hides parked windows without hiding apps); it decodes
-- the wallpaper, the slowest step (~1.5 s), so it comes last.
wsHide = timed("ws-hide")
marginVeil = timed("margin-veil")
-- hs.image / canvas / task objects hold native memory the Lua GC does not count, so it rarely runs on its own.
gcTimer = hs.timer.doEvery(300, function() collectgarbage() end)
startupTimes[#startupTimes + 1] = string.format("total %.0f ms", (hs.timer.absoluteTime() - t0) / 1e6)
