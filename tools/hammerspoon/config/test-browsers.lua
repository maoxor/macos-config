-- Browsers driven by Playwright (Claude Code experiments) open on workspace 4: OmniWM rules, and patch 0029
-- for their later windows and to keep the view where it is. macOS still hands them the keyboard: when one
-- becomes frontmost without a click from the user in the last second, focus goes straight back to the app that
-- had it. Clicking into such a browser on workspace 4 still works. (Polled: these apps are often not reported
-- by hs.application.watcher.) Safari windows a session forces to float are moved to
-- workspace 4 on each OmniWM windows-changed event.
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
local moving = false
local function sweep()
  if moving then return end
  moving = true
  hs.task.new(CTL, function(_, out)
    local ok, data = pcall(hs.json.decode, out or "")
    local ids = {}
    if ok and data and data.result then
      for _, w in ipairs(data.result.payload.windows or {}) do
        -- Safari windows that a session forced to float (AppleScript + toggle-focused-window-floating).
        local driven = w.app.bundleId == "com.apple.Safari" and w.manualOverride == "force-float"
        if driven and w.workspace and w.workspace.number ~= 4 then ids[#ids + 1] = w.id end
      end
    end
    for _, id in ipairs(ids) do hs.task.new(CTL, nil, { "window", "move-to-workspace", id, "4" }):start() end
    moving = false
  end, { "query", "windows", "--format", "json" }):start()
end

M.debounce = hs.timer.delayed.new(0.4, sweep)

local function subscribe()
  M.sub = hs.task.new(CTL, function() hs.timer.doAfter(5, subscribe) end, function()
    M.debounce:start() -- one query per burst of window events
    return true
  end, { "subscribe", "windows-changed", "--no-send-initial", "--format", "ndjson" })
  M.sub:start()
end
subscribe()

return M
