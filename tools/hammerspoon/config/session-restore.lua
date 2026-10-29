-- Cmd+F5: reopen what a crash closed (apps, Claude Code sessions on their workspace) with
-- scripts/restore-session.py; the snapshot is written every minute by scripts/session-snapshot.py.
-- Bound on Cmd+fn+F5 (real F5) and on what the bare F5 key sends: Dictation (keycode 176) or keyboard
-- backlight down (ILLUMINATION_DOWN) depending on the keyboard.
local M = {}
local repo = require("repo-path")
local logFile = os.getenv("HOME") .. "/Library/Logs/restore-session.log"

function M.restore()
  if M.task and M.task:isRunning() then return end
  hs.alert.show("Restauration de la session…")
  M.task = hs.task.new("/bin/bash", function(code)
    hs.alert.show(code == 0 and "Session restaurée" or "Restauration : erreur (voir restore-session.log)")
  end, { "-c", "/usr/bin/python3 " .. repo .. "/scripts/restore-session.py >> " .. logFile .. " 2>&1" })
  M.task:start()
end

M.hotkey = hs.hotkey.bind({ "cmd" }, "f5", M.restore)

local types = hs.eventtap.event.types
M.tap = hs.eventtap.new({ types.keyDown, types.systemDefined }, function(e)
  local f = e:getFlags()
  if not (f.cmd and not f.alt and not f.ctrl and not f.shift) then return false end
  if e:getType() == types.systemDefined then
    local k = e:systemKey()
    if k.key ~= "ILLUMINATION_DOWN" then return false end
    if k.down and not k["repeat"] then M.restore() end
    return true
  end
  if e:getKeyCode() ~= 176 then return false end
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then M.restore() end
  return true
end)
M.tap:start()

return M
