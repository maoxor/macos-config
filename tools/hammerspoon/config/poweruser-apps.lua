-- SPDX-License-Identifier: MIT
-- App shortcuts. Cmd+E = Finder.
-- Overrides Cmd+E everywhere (Finder: Eject; Safari/Notes: Use Selection for Find).
local M = {}

local function finder()
  local app = hs.application.get("com.apple.finder")
  local hasWindow = false
  if app then
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() then hasWindow = true; break end
    end
  end
  if hasWindow then
    hs.application.launchOrFocusByBundleID("com.apple.finder")
  else
    -- No Finder window: open one on the home folder
    hs.task.new("/usr/bin/open", nil, { os.getenv("HOME") }):start()
  end
end

M.finder = hs.hotkey.bind({ "cmd" }, "e", finder)

-- Closing the last Finder window leaves Finder frontmost with no window: keystrokes go nowhere and OmniWM's
-- focus-follows-mouse treats Finder as an external focus, so even moving the mouse does not refocus.
-- Give the focus back to the standard window under the mouse.
local function windowUnderMouse()
  local p = hs.mouse.absolutePosition()
  for _, w in ipairs(hs.window.orderedWindows()) do
    if w:isStandard() and w:application():bundleID() ~= "com.apple.finder" and hs.geometry.point(p):inside(w:frame()) then
      return w
    end
  end
end

local function refocusIfFinderIsEmpty()
  hs.timer.doAfter(0.3, function()
    local app = hs.application.get("com.apple.finder")
    if not app or not app:isFrontmost() then return end
    for _, w in ipairs(app:allWindows()) do
      if w:isStandard() and w:isVisible() then return end
    end
    local target = windowUnderMouse()
    if target then target:focus() end
  end)
end

-- An accessibility observer on Finder alone, not hs.window.filter: a filter scans every window of every app
-- when created, which took 21 s at Hammerspoon start (no shortcut works meanwhile, 2026-10-29).
local function watchFinder()
  local app = hs.application.get("com.apple.finder")
  if M.finderObserver then M.finderObserver:stop(); M.finderObserver = nil end
  if not app then return end
  M.finderObserver = hs.axuielement.observer.new(app:pid())
    :callback(refocusIfFinderIsEmpty)
    :addWatcher(hs.axuielement.applicationElement(app), "AXUIElementDestroyed")
  M.finderObserver:start()
end
watchFinder()
M.finderRelaunch = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.launched and app and app:bundleID() == "com.apple.finder" then watchFinder() end
end)
M.finderRelaunch:start()
return M
