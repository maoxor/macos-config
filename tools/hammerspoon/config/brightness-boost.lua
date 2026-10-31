-- Cmd+F3: XDR brightness boost on / off (scripts/xdr-boost.swift). The running process is the state: pkill says
-- whether it was on, so a Hammerspoon restart loses nothing.
local M = {}
local tool = os.getenv("HOME") .. "/.local/bin/xdr-boost"

local function start()
  M.task = hs.task.new("/bin/bash", function(code, _, err)
    if code ~= 0 then hs.alert.show("Boost impossible : " .. (err or ""):gsub("%s+$", "")) end
  end, { tool })
  M.task:start()
  hs.alert.show("Luminosité boostée")
end

function M.toggle()
  hs.task.new("/usr/bin/pkill", function(code)
    if code == 0 then hs.alert.show("Luminosité normale") else start() end
  end, { "-x", "xdr-boost" }):start()
end

M.hotkey = hs.hotkey.bind({ "cmd" }, "f3", M.toggle)

-- The built-in keyboard sends keycode 160 for F3; created after function-keys.lua, which drops it, so it runs first.
M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  if e:getKeyCode() ~= 160 then return false end
  local f = e:getFlags()
  if not (f.cmd and not f.alt and not f.ctrl and not f.shift) then return false end
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then M.toggle() end
  return true
end)
M.tap:start()

return M
