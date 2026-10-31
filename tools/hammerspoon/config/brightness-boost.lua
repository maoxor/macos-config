-- The brightness keys go on past 100 % into the XDR boost (scripts/xdr-boost.swift, which also draws the level bar):
-- F2 starts it at the press after 100 %, four steps up to 1000 nits, F1 comes back down and stops it. Below 100 % they
-- stay macOS's.
local M = { level = 0 }
local tool = os.getenv("HOME") .. "/.local/bin/xdr-boost"
local steps = 4
local gain = 1 + 0.67 / steps  -- first step; scripts/xdr-boost.swift owns the ceiling

hs.task.new("/usr/bin/pkill", nil, { "-x", "xdr-boost" }):start()  -- a boost left by the previous Hammerspoon

local function signal(name)
  hs.task.new("/usr/bin/pkill", nil, { name, "-x", "xdr-boost" }):start()
end

function M.up()
  if M.level == 0 then
    M.level = 1
    local task
    task = hs.task.new("/bin/bash", function(code, _, err)
      if M.task ~= task then return end  -- an older boost, still fading out
      M.level, M.task = 0, nil
      if code ~= 0 then hs.alert.show("Boost impossible : " .. (err or ""):gsub("%s+$", "")) end
    end, { tool, tostring(gain) })
    M.task = task
    task:start()
  else
    M.level = math.min(M.level + 1, steps)
    signal("-USR1")  -- at the top too: it shows the bar again
  end
end

function M.down()
  M.level = M.level - 1
  signal(M.level == 0 and "-TERM" or "-USR2")
end

local owned = {}
M.tap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  local k = e:systemKey()
  if k.key ~= "BRIGHTNESS_UP" and k.key ~= "BRIGHTNESS_DOWN" then return false end
  local f = e:getFlags()
  if f.cmd or f.alt or f.ctrl or f.shift then return false end
  local up = k.key == "BRIGHTNESS_UP"
  -- One press belongs to one side from start to end: macOS must not get a release without its press.
  if k.down and not k["repeat"] then
    owned[k.key] = M.level > 0 or (up and hs.brightness.get() >= 100)
  end
  if not owned[k.key] then return false end
  if k.down and (up or M.level > 0) then
    if up then M.up() else M.down() end
  end
  return true
end)
M.tap:start()

return M
