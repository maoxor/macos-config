-- Cmd+F5 twice: reopen what a crash closed (apps, Claude Code sessions on their workspace) with
-- scripts/restore-session.py; the snapshot is written every minute by scripts/session-snapshot.py.
-- One press only announces it: a stray press after a normal shutdown brought every closed session back (B23).
-- Bound on Cmd+fn+F5 (real F5) and on what the bare F5 key sends: Dictation (keycode 176) or keyboard
-- backlight down (ILLUMINATION_DOWN) depending on the keyboard.
local M = {}
local repo = require("repo-path")
local logFile = os.getenv("HOME") .. "/Library/Logs/restore-session.log"
local stateDir = os.getenv("HOME") .. "/.local/state/session-snapshot/"
local BOUNCE, WINDOW = 0.4, 5 -- one press can send two events; the second press must come within 5 s

function M.restore()
  if M.task and M.task:isRunning() then return end
  hs.alert.show("Restauration de la session…")
  M.task = hs.task.new("/bin/bash", function(code)
    hs.alert.show(code == 0 and "Session restaurée" or "Restauration : erreur (voir restore-session.log)")
  end, { "-c", "/usr/bin/python3 " .. repo .. "/scripts/restore-session.py >> " .. logFile .. " 2>&1" })
  M.task:start()
end

-- The conversations restore-session.py would reopen: the same file it picks.
local function pendingNames()
  local ok, snap = pcall(hs.json.read, stateDir .. "previous-boot.json")
  if not (ok and snap) then ok, snap = pcall(hs.json.read, stateDir .. "current.json") end
  local names = {}
  for _, s in ipairs(ok and snap and snap.sessions or {}) do names[#names + 1] = s.name or "sans nom" end
  return names
end

function M.press()
  if M.task and M.task:isRunning() then return end
  local now = hs.timer.secondsSinceEpoch()
  local since = M.armedAt and now - M.armedAt
  if since and since < BOUNCE then return end
  if since and since < WINDOW then
    M.armedAt = nil
    return M.restore()
  end
  M.armedAt = now
  local names = pendingNames()
  hs.alert.show(#names > 0 and ("Cmd+F5 encore une fois pour rouvrir : " .. table.concat(names, ", "))
    or "Cmd+F5 encore une fois pour rouvrir Ghostty, Safari et Discord", WINDOW)
end

M.hotkey = hs.hotkey.bind({ "cmd" }, "f5", M.press)

local types = hs.eventtap.event.types
M.tap = hs.eventtap.new({ types.keyDown, types.systemDefined }, function(e)
  local f = e:getFlags()
  if not (f.cmd and not f.alt and not f.ctrl and not f.shift) then return false end
  if e:getType() == types.systemDefined then
    local k = e:systemKey()
    if k.key ~= "ILLUMINATION_DOWN" then return false end
    if k.down and not k["repeat"] then M.press() end
    return true
  end
  if e:getKeyCode() ~= 176 then return false end
  if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then M.press() end
  return true
end)
M.tap:start()

return M
