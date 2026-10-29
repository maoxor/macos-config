-- Playwright test browsers (Claude Code experiments) live on workspace 4: OmniWM rules place them there, patch
-- 0029 keeps their later windows there without switching the view, and scripts/playwright-background-pages.py
-- opens their pages behind the user's windows. macOS still hands them the keyboard: when one becomes frontmost
-- without a click from the user in the last second, focus goes back to the app that had it (polled: these apps
-- are often not reported by hs.application.watcher). Also moves Safari windows a session forced to float to
-- workspace 4 (checked every 2 s).
local M = {}
M.bundles = {
  ["com.google.chrome.for.testing"] = true, ["org.chromium.Chromium"] = true,
  ["org.webkit.Playwright"] = true, ["org.mozilla.nightlyunofficial"] = true,
}
local lastClick, last = 0, nil

M.clicks = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function()
  lastClick = hs.timer.secondsSinceEpoch()
  return false
end)
M.clicks:start()

local testSeen = 0 -- last time a test browser was frontmost
M.timer = hs.timer.doEvery(0.25, function()
  local app = hs.application.frontmostApplication()
  if not app then return end
  local now = hs.timer.secondsSinceEpoch()
  if M.bundles[app:bundleID() or ""] then
    testSeen = now
    if now - lastClick > 1 and last and last:isRunning() then last:activate() end
  elseif now - testSeen < 3 and app ~= last and now - lastClick > 1 and last and last:isRunning() then
    -- A test browser that just quit leaves the keyboard to whatever macOS picks (often a menu bar app).
    last:activate()
  else
    last = app
  end
end)

local CTL = os.getenv("HOME") .. "/.local/bin/omniwmctl"
-- Every 2 s, a short query of the floating Safari windows only. Not "omniwmctl subscribe": hs.task keeps the
-- whole output of a task that never ends, and that stream grew Hammerspoon to 4.6 GB (2026-10-29).
local busy = false
local function sweep()
  if busy then return end
  busy = true
  M.task = hs.task.new(CTL, function(_, out)
    busy = false
    local ok, data = pcall(hs.json.decode, out or "")
    if not (ok and data and data.result) then return end
    for _, w in ipairs(data.result.payload.windows or {}) do
      if w.manualOverride == "force-float" and w.workspace and w.workspace.number ~= 4 then
        hs.task.new(CTL, nil, { "window", "move-to-workspace", w.id, "4" }):start()
      end
    end
  end, { "query", "windows", "--bundle-id", "com.apple.Safari", "--floating", "--format", "json" })
  M.task:start()
end
M.sweepTimer = hs.timer.doEvery(2, sweep)

return M
