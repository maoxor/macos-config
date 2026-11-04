-- F3 (Mission Control, keycode 160) and F4 (Spotlight 177, Launchpad 131 on older keyboards) do nothing:
-- the Mac stays usable only through its own shortcuts. Bare F3 / F4 are taken first by wallpaper-cycle.lua and
-- keyboard-clean.lua (eventtaps created later run first).
local M = {}
-- Opt-in: home-manager creates this file when profile.nix sets lockDown.
if not hs.fs.attributes(os.getenv("HOME") .. "/.config/macos-config/lock-down") then return M end
local blocked = { [160] = true, [177] = true, [131] = true }

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(e)
  if not blocked[e:getKeyCode()] then return false end
  -- Cmd alone + F3 (160) is the free XAU prompt (prompt-insert.lua, whose tap runs after this one): let it through.
  local f = e:getFlags()
  if e:getKeyCode() == 160 and f.cmd and not (f.alt or f.ctrl or f.shift) then return false end
  return true
end)
M.tap:start()

return M
