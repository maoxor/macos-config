-- Margin veil (2026-10-09).
-- OmniWM parks windows of inactive workspaces 1 px inside the right screen edge; their edge and
-- shadow darken the 8 px right outer gap. Hiding their apps removed the strip but made workspace
-- swipes "pop" (hidden apps cannot slide in with the gesture). Instead, a click-through strip that
-- shows the matching slice of the wallpaper covers that gap, above the parked windows. Tiled
-- windows stop at the gap, so nothing useful is covered; the veil hides itself whenever a window
-- of the active workspace reaches into the gap (temporary fullscreen, drag).
local M = {}
local GAP = 8          -- gaps.outer.right
local TOP = 32         -- menu bar / notch band (the veil never covers it)
M.FALLBACK = require("repo-path") .. "/wallpapers/actuel.png"  -- kept by theme-auto

local function topFor(screen)
  -- Height of the notch/menu-bar band in points: depends on the display mode (32 at 1728x1117,
  -- 39 at 2074x1340), so read it from the screen instead of a constant.
  local band = screen:frame().y - screen:fullFrame().y
  return band > 0 and band or TOP
end

local function frameFor(screen)
  local f = screen:fullFrame()
  local top = topFor(screen)
  return { x = f.x + f.w - GAP, y = f.y + top, w = GAP, h = f.h - top }, f
end

local SLICE = os.getenv("HOME") .. "/Library/Caches/macos-config-margin-veil.png"

-- The canvas shows only the gap slice of the wallpaper, cut by sips into a small file: decoding the full
-- picture in Hammerspoon (3840x4267) left ~500 MB of image memory behind on every rebuild (2026-10-29).
local function paint(rect, slicePath)
  if M.canvas then M.canvas:delete() end
  local image = slicePath and hs.image.imageFromPath(slicePath)
  local c = hs.canvas.new(rect)
  -- Just above normal windows, BELOW OmniWM's overlays: raised to status level (2026-10-15) it
  -- painted over swipe previews and Niri columns sliding through the edge (a "transparent
  -- column" on the right). The last point is OmniWM's ParkingEdgeMask, which now shows the
  -- wallpaper and swallows clicks itself (local OmniWM patch).
  c:level(hs.canvas.windowLevels.normal + 1)
  c:behavior({ "canJoinAllSpaces", "stationary", "ignoresCycle" })
  c:clickActivating(false)
  -- Swallow clicks: the gap holds nothing clickable, and a click-through veil let clicks reach the
  -- 1 px of a parked inactive-workspace window under it, which focused it and switched workspace.
  c:canvasMouseEvents(true, true, false, false)
  c:mouseCallback(function() end)
  if image then
    c[1] = { type = "image", image = image, imageScaling = "scaleToFit", frame = { x = 0, y = 0, w = rect.w, h = rect.h } }
  else
    c[1] = { type = "rectangle", action = "fill", fillColor = { white = 0.05 } }
  end
  M.canvas = c
  M.shown = not M.suppressed
  if M.shown then c:show() end
end

function M.build()
  local screen = hs.screen.mainScreen()
  local rect, full = frameFor(screen)
  -- macOS keeps showing a wallpaper whose source file was deleted (e.g. a cleaned Downloads
  -- folder) while desktopImageURL still points at it: fall back to the copy theme-auto keeps in
  -- the repo. Never draw the dark fallback fill: an opaque 8 px dark bar is the bug it fixes.
  local url = screen:desktopImageURL()
  local path = url and hs.http.urlParts(url).path
  path = path and hs.http.convertHtmlEntities(path):gsub("%%20", " ")
  if not (path and hs.fs.attributes(path)) then path = M.FALLBACK end
  if M.canvas and M.path == path and M.rect and M.rect.h == rect.h and M.rect.y == rect.y then return end
  M.path, M.rect = path, rect
  local top = topFor(screen)
  hs.task.new("/usr/bin/sips", function(_, out)
    local pw, ph = tonumber(out:match("pixelWidth: (%d+)")), tonumber(out:match("pixelHeight: (%d+)"))
    if not (pw and ph) then return paint(rect, nil) end
    -- Reproduce macOS "Fill screen": scale to cover, centered; keep the pixels under the gap.
    local k = math.max(full.w / pw, full.h / ph)
    local x = math.floor(((full.w - GAP) - (full.w - pw * k) / 2) / k)
    local y = math.floor((top - (full.h - ph * k) / 2) / k)
    local w, h = math.max(1, math.ceil(GAP / k)), math.ceil(rect.h / k)
    hs.task.new("/usr/bin/sips", function(code)
      paint(rect, code == 0 and SLICE or nil)
    end, { "-c", tostring(h), tostring(w), "--cropOffset", tostring(y), tostring(x), path, "--out", SLICE }):start()
  end, { "-g", "pixelWidth", "-g", "pixelHeight", path }):start()
end

-- Called with the OmniWM window list of the active workspace (bottom-left origin frames).
function M.update(windows, activeId)
  if not M.canvas then M.build() end
  local full = hs.screen.mainScreen():fullFrame()
  local limit = full.w - GAP
  -- Only a real intrusion (fullscreen, drag: more than half the gap) hides the veil. Terminals
  -- round their width to the character grid and overshoot the gap by 1-2 pt (Ghostty on Focus:
  -- 1813+254 = 2067 > 2066); treating that as an intrusion hid the veil on that workspace only
  -- and uncovered the parked windows' edges and shadows (2026-10-15).
  local function hits(x, width) return x < limit - 1 and x + width > limit + GAP / 2 end
  local intrudes = false
  for _, w in ipairs(windows or {}) do
    if w.workspace and w.workspace.id == activeId and hits(w.frame.x, w.frame.width) then
      -- Confirm with the REAL frame: for a Niri column scrolled off screen OmniWM reports its
      -- layout slot (Web column 3: x=1049) while the window is parked at the right edge (x=2073),
      -- which hid the veil on every Niri workspace with an off-screen column. hs.window.get walks
      -- the AX tree, so it is only called for candidates.
      local real = w.windowId and hs.window.get(w.windowId)
      local r = real and real:frame()
      if not r or hits(r.x, r.w) then intrudes = true end
    end
  end
  M.suppressed = intrudes
  -- Called after every OmniWM window change: only touch the window server when the state flips.
  if M.shown == not intrudes then return end
  M.shown = not intrudes
  if intrudes then M.canvas:hide() else M.canvas:show() end
end

M.build()
-- Resolution change: rebuild. Wallpaper change: macOS rewrites its wallpaper index (the file the
-- theme-auto LaunchAgent also watches); rebuild once it settled. Event-driven, no polling.
M.screenWatcher = hs.screen.watcher.new(function()
  if M.canvas then M.canvas:delete(); M.canvas = nil end
  M.build()
end)
M.screenWatcher:start()
M.wallpaperRebuild = hs.timer.delayed.new(1.5, function() M.build() end)
M.wallpaperWatcher = hs.pathwatcher.new(
  os.getenv("HOME") .. "/Library/Application Support/com.apple.wallpaper/Store/Index.plist",
  function() M.wallpaperRebuild:start() end)
M.wallpaperWatcher:start()
return M
