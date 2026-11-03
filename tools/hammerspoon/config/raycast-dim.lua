-- Raycast backdrop (2026-11-03): while Raycast's launcher panel is on screen, everything behind it is dimmed so the
-- eye goes to the search field. Raycast has no such setting. Its panel does not activate Raycast (the front app
-- stays the user's), so an application watcher never sees it: an Accessibility observer reports each panel Raycast
-- shows, and Cmd+Space (its hotkey) is watched passively as a second trigger; while the backdrop is up the window
-- list is checked every 100 ms (~3 ms each) until the panel is gone. Only the launcher counts (layer 8, larger than a
-- toast); Raycast's Settings and AI Chat are normal windows and dim nothing.
-- The backdrop sits one level below the panel and ignores the mouse (a click outside still closes Raycast, as
-- before); the menu bar and the Dock stay above it when they show. Off: `hs -c 'raycastDim.stop()'`; for good,
-- remove the module from init.lua.
-- Ring: the panel also gets the focused-window border, which JankyBorders cannot draw on a panel. Colour and width
-- are read from JankyBorders' own config (home-manager/borders.nix -> ~/.config/borders/bordersrc), so both borders
-- always match; the ring sits outside the panel's edge, under it, and follows it when Raycast resizes. No
-- bordersrc (JankyBorders off) = no ring.
local M = {}
M.alpha = 0.45       -- darkness of the backdrop
M.fade = 0.12        -- seconds
local BUNDLE = "com.raycast.macos"
local PANEL_LAYER = 8          -- NSModalPanelWindowLevel, measured by window-journal
local MIN_AREA = 120000        -- pt²: the launcher is 460x390 or larger, a HUD toast is much smaller
M.radius = 20                  -- corner radius of the launcher panel (measured on macOS 26)
local poll, observer, observedPid, canvases = nil, nil, nil, {}
M.shows = { ax = 0, key = 0 }   -- which trigger showed the backdrop (`hs -c 'return raycastDim.status()'`)

-- Bounds of the launcher panel, or nil.
local function panelOnScreen()
  for _, w in ipairs(hs.window.list(false)) do
    if w.kCGWindowOwnerName == "Raycast" and w.kCGWindowLayer == PANEL_LAYER then
      local b = w.kCGWindowBounds
      if b and b.Width * b.Height >= MIN_AREA then return b end
    end
  end
  return nil
end

-- Colour and width of the focused-window border, from JankyBorders' config; nil when JankyBorders is off (no
-- bordersrc), and then the panel gets no ring either.
local function ringStyle()
  local f = io.open(os.getenv("HOME") .. "/.config/borders/bordersrc")
  if not f then return nil end
  local txt = f:read("a"); f:close()
  local a, r, g, b = txt:match("active_color=0x(%x%x)(%x%x)(%x%x)(%x%x)")
  if not a then return nil end
  local color = { alpha = tonumber(a, 16) / 255, red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
    blue = tonumber(b, 16) / 255 }
  return color, tonumber(txt:match("width=([%d%.]+)")) or 4
end

-- Place the ring around the panel on every backdrop canvas (each canvas covers one screen).
local function placeRing(b)
  local color, w = ringStyle()
  for _, c in ipairs(canvases) do
    if color then
      local sf = c:frame()
      c[2].frame = { x = b.X - sf.x - w / 2, y = b.Y - sf.y - w / 2, w = b.Width + w, h = b.Height + w }
      c[2].strokeWidth = w
      c[2].strokeColor = color
      c[2].roundedRectRadii = { xRadius = M.radius + w / 2, yRadius = M.radius + w / 2 }
    else
      c[2].frame = { x = -100, y = -100, w = 10, h = 10 }
    end
  end
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
    c[2] = { type = "rectangle", action = "stroke", frame = { x = -100, y = -100, w = 10, h = 10 } }
    canvases[#canvases + 1] = c
  end
end

local function show()
  if poll then return end
  local b = panelOnScreen()
  if not b then return false end
  if #canvases == 0 then build() end
  placeRing(b)
  for _, c in ipairs(canvases) do c:show(M.fade) end
  local last = b
  poll = hs.timer.doEvery(0.1, function()
    local now = panelOnScreen()
    if not now then hide(); return end
    if now.X ~= last.X or now.Y ~= last.Y or now.Width ~= last.Width or now.Height ~= last.Height then
      placeRing(now); last = now
    end
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
