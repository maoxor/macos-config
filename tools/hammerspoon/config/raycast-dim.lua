-- Raycast backdrop (2026-11-03): while Raycast's launcher panel is on screen, everything behind it is dimmed so the
-- eye goes to the search field. Raycast has no such setting. Its panel does not activate Raycast (the front app
-- stays the user's), so an application watcher never sees it: an Accessibility observer reports each panel Raycast
-- shows, and Cmd+Space (its hotkey) is watched passively as a second trigger; while the backdrop is up the window
-- list is checked every 100 ms (~3 ms each) until the panel is gone. Only the launcher counts (layer 8, larger than a
-- toast); Raycast's Settings and AI Chat are normal windows and dim nothing.
-- The backdrop sits one level below the panel and ignores the mouse (a click outside still closes Raycast, as
-- before); the menu bar and the Dock stay above it when they show. Off: `hs -c 'raycastDim.stop()'`; for good,
-- remove the module from init.lua.
local M = {}
M.alpha = 0.45       -- darkness of the backdrop
M.fade = 0.12        -- seconds
local BUNDLE = "com.raycast.macos"
local PANEL_LAYER = 8          -- NSModalPanelWindowLevel, measured by window-journal
local MIN_AREA = 120000        -- pt²: the launcher is 460x390 or larger, a HUD toast is much smaller
local poll, observer, observedPid, canvases = nil, nil, nil, {}
M.shows = { ax = 0, key = 0 }   -- which trigger showed the backdrop (`hs -c 'return raycastDim.status()'`)

local function panelOnScreen()
  for _, w in ipairs(hs.window.list(false)) do
    if w.kCGWindowOwnerName == "Raycast" and w.kCGWindowLayer == PANEL_LAYER then
      local b = w.kCGWindowBounds
      if b and b.Width * b.Height >= MIN_AREA then return true end
    end
  end
  return false
end

local function hide()
  if poll then poll:stop(); poll = nil end
  for _, c in ipairs(canvases) do c:hide(M.fade) end
end

local function build()
  for _, c in ipairs(canvases) do c:delete() end
  canvases = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local c = hs.canvas.new(screen:fullFrame())
    c:level(PANEL_LAYER - 1)
    c:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle", "transient" })
    c:clickActivating(false)
    c[1] = { type = "rectangle", action = "fill", fillColor = { white = 0, alpha = M.alpha } }
    canvases[#canvases + 1] = c
  end
end

local function show()
  if poll then return end
  if not panelOnScreen() then return false end
  if #canvases == 0 then build() end
  for _, c in ipairs(canvases) do c:show(M.fade) end
  poll = hs.timer.doEvery(0.1, function()
    if not panelOnScreen() then hide() end
  end)
  return true
end

-- The panel takes a few ms to appear after an event: look again a few times.
local function showSoon(source)
  local tries = 0
  local function try()
    tries = tries + 1
    local r = show()
    if r == true then M.shows[source] = M.shows[source] + 1 end
    if r == false and tries < 6 then hs.timer.doAfter(0.05, try) end
  end
  hs.timer.doAfter(0.02, try)
end

local function attach(app)
  if observer then observer:stop(); observer = nil end
  observedPid = nil
  if not app then return end
  local ok, obs = pcall(hs.axuielement.observer.new, app:pid())
  if not ok or not obs then return end
  obs:callback(function() showSoon("ax") end)
  local element = hs.axuielement.applicationElement(app)
  -- Raycast reuses its panel: besides creation, a show makes it the focused window.
  for _, n in ipairs({ "AXWindowCreated", "AXFocusedWindowChanged", "AXApplicationActivated" }) do
    obs:addWatcher(element, n)
  end
  obs:start()
  observer, observedPid = obs, app:pid()
end

local SPACE = hs.keycodes.map.space

function M.start()
  attach(hs.application.get(BUNDLE))
  -- Passive: the key still goes to Raycast.
  M.keys = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
    if e:getKeyCode() == SPACE
        and e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then
      local f = e:getFlags()
      if f.cmd and not (f.alt or f.ctrl or f.shift) then showSoon("key") end
    end
    return false
  end):start()
  -- Raycast restarts (updates, crash): follow its new process.
  M.apps = hs.application.watcher.new(function(_, event, app)
    if app and app:bundleID() == BUNDLE and (event == hs.application.watcher.launched
        or event == hs.application.watcher.terminated) then
      hide()
      attach(event == hs.application.watcher.launched and app or nil)
    end
  end):start()
  -- New display mode or screen: rebuild the backdrop at the next show.
  M.screens = hs.screen.watcher.new(function() hide(); for _, c in ipairs(canvases) do c:delete() end; canvases = {} end):start()
end

function M.stop()
  hide()
  if observer then observer:stop(); observer = nil end
  if M.apps then M.apps:stop() end
  if M.keys then M.keys:stop() end
  if M.screens then M.screens:stop() end
end

function M.status()
  return string.format("observer=%s pid=%s shown=%s shows: ax=%d key=%d", tostring(observer ~= nil), tostring(observedPid),
    tostring(poll ~= nil), M.shows.ax, M.shows.key)
end

M.start()
return M
