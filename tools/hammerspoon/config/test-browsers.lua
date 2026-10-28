-- Browsers driven by Playwright (Claude Code experiments) open on workspace 4 (OmniWM rule), but they take focus
-- and OmniWM follows them there. When one becomes frontmost without a click from the user in the last second,
-- focus goes straight back to the app that had it, so the user stays on their workspace. Clicking into such a
-- browser on workspace 4 still works. (Polled: these apps are often not reported by hs.application.watcher.)
-- The OmniWM rule only places an app's first window; later ones (new pages) are moved to workspace 4 on each
-- OmniWM windows-changed event.
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

M.timer = hs.timer.doEvery(0.25, function()
  local app = hs.application.frontmostApplication()
  if not app then return end
  if not M.bundles[app:bundleID() or ""] then last = app return end
  if hs.timer.secondsSinceEpoch() - lastClick > 1 and last and last:isRunning() then last:activate() end
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
        if M.bundles[w.app.bundleId or ""] and w.workspace and w.workspace.number ~= 4 then ids[#ids + 1] = w.id end
      end
    end
    for _, id in ipairs(ids) do hs.task.new(CTL, nil, { "window", "move-to-workspace", id, "4" }):start() end
    moving = false
  end, { "query", "windows", "--format", "json" }):start()
end

local function subscribe()
  M.sub = hs.task.new(CTL, function() hs.timer.doAfter(5, subscribe) end, function(_, out)
    sweep()
    return true
  end, { "subscribe", "windows-changed", "--no-send-initial", "--format", "ndjson" })
  M.sub:start()
end
subscribe()

return M
