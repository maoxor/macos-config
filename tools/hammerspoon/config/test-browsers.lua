-- Playwright test browsers (Claude Code experiments) live on workspace 4: OmniWM rules place them there, patch
-- 0029 keeps their later windows there without switching the view, and scripts/playwright-background-pages.py
-- opens their pages behind the user's windows. macOS still hands them the keyboard: when one becomes frontmost
-- without a click from the user in the last second, focus goes back to the app that had it (polled: these apps
-- are often not reported by hs.application.watcher), unless the user is on the browser's workspace: it is theirs
-- there (a sign-in window), and giving focus back would throw them off that workspace. Also moves Safari windows a
-- session forced to float to workspace 4 (on each OmniWM window change).
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

-- A Chrome, Edge or Brave a driver launched is a test browser too (same test as OmniWM patch 0030, which sends its
-- windows to workspace 4): --remote-debugging-pipe (Playwright channel "chrome"), --remote-debugging-port=0 or
-- --enable-automation (Puppeteer, Selenium). Its arguments are read once a minute per pid (a pid can be reused).
local automation = {}
local function isTest(app)
  local bid = app:bundleID() or ""
  if M.bundles[bid] then return true end
  if not (bid:find("^com%.google%.Chrome") or bid:find("^com%.microsoft%.edgemac") or bid:find("^com%.brave%.Browser")) then
    return false
  end
  local pid, now = app:pid(), hs.timer.secondsSinceEpoch()
  local known = automation[pid]
  if not known or now - known.at > 60 then
    local out = hs.execute("/bin/ps -ww -o args= -p " .. pid) or ""
    local args = " " .. out:gsub("%s+$", "") .. " "
    known = { at = now, test = args:find(" --enable-automation ", 1, true) ~= nil
      or args:find(" --remote-debugging-pipe ", 1, true) ~= nil or args:find(" --remote-debugging-port=0 ", 1, true) ~= nil }
    automation[pid] = known
  end
  return known.test
end
M.isTest = isTest

local function onActiveWorkspace(app)
  local pid = app:pid()
  for _, w in ipairs(wsHide and wsHide.windows or {}) do
    if w.pid == pid and w.workspace and w.workspace.id == wsHide.activeId then return true end
  end
  return false
end

local testSeen = 0 -- last time a test browser took focus
M.timer = hs.timer.doEvery(0.25, function()
  local app = hs.application.frontmostApplication()
  if not app then return end
  local now = hs.timer.secondsSinceEpoch()
  if isTest(app) and not onActiveWorkspace(app) then
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
-- Safari windows a session forced to float go to workspace 4. Checked on every window list ws-hide.lua receives
-- from OmniWM (windows-changed events: the move follows at once); a query every 60 s covers a missed event. (It
-- was a query every 2 s: an omniwmctl process each time, ~2 ms of CPU, and up to 2 s of delay.)
local moved = {}
function M.onWindows(windows)
  for _, w in ipairs(windows or {}) do
    if w.manualOverride == "force-float" and w.app and w.app.bundleId == "com.apple.Safari"
      and w.workspace and w.workspace.number ~= 4 and not moved[w.id] then
      moved[w.id] = true
      hs.task.new(CTL, function() moved[w.id] = nil end, { "window", "move-to-workspace", w.id, "4" }):start()
    end
  end
end
local busy = false
local function sweep()
  if busy then return end
  busy = true
  M.task = hs.task.new(CTL, function(_, out)
    busy = false
    local ok, data = pcall(hs.json.decode, out or "")
    if ok and data and data.result then M.onWindows(data.result.payload.windows) end
  end, { "query", "windows", "--bundle-id", "com.apple.Safari", "--floating", "--format", "json" })
  M.task:start()
end
M.sweepTimer = hs.timer.doEvery(60, sweep)

return M
