-- Cmd+Shift+F in a browser (2026-11-04): OmniWM's fullscreen instead of macOS's native one. Native fullscreen moves
-- the window to its own Space, where SketchyBar is not drawn: the band above the notch turns black and the macOS menu
-- bar slides in there. OmniWM's fullscreen keeps the window on its workspace and fills the screen under the top bar.
-- The same keys exit. Other apps keep their own Cmd+Shift+F. Off: remove the module from init.lua.
local M = {}
M.browsers = { ["app.zen-browser.zen"] = true, ["net.imput.helium"] = true, ["com.apple.Safari"] = true }
local F = hs.keycodes.map.f
local CTL = os.getenv("HOME") .. "/.local/bin/omniwmctl"

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  if e:getKeyCode() ~= F then return false end
  local f = e:getFlags()
  if not (f.cmd and f.shift) or f.alt or f.ctrl then return false end
  local app = hs.application.frontmostApplication()
  if not (app and M.browsers[app:bundleID()]) then return false end
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0 then return true end
  M.task = hs.task.new(CTL, nil, { "command", "toggle-fullscreen" })
  M.task:start()
  return true
end):start()

return M
