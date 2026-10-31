-- The brightness keys go on past 100 % into the XDR boost (scripts/xdr-boost.swift): F2 starts it at the fifth press,
-- four steps up to 1000 nits, F1 comes back down and stops it. Below 100 % they stay macOS's. Apple's bar cannot be
-- extended, so these steps show a bar drawn in its style.
local M = { level = 0 }
local tool = os.getenv("HOME") .. "/.local/bin/xdr-boost"
local steps = 4
local gain = 1 + 0.67 / steps  -- first step; scripts/xdr-boost.swift owns the ceiling

hs.task.new("/usr/bin/pkill", nil, { "-x", "xdr-boost" }):start()  -- a boost left by the previous Hammerspoon

local function signal(name)
  hs.task.new("/usr/bin/pkill", nil, { name, "-x", "xdr-boost" }):start()
end

local bar
local function show()
  local screen = hs.screen.primaryScreen():fullFrame()
  local width, height, cell, gap = 228, 46, 34, 4
  if bar then bar:delete() end
  bar = hs.canvas.new({ x = screen.x + screen.w - width - 16, y = screen.y + 12, w = width, h = height })
  bar:level(hs.canvas.windowLevels.overlay)
  bar:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
  bar:appendElements({ type = "rectangle", action = "fill", fillColor = { white = 0.13, alpha = 0.88 },
    roundedRectRadii = { xRadius = 16, yRadius = 16 } })
  bar:appendElements({ type = "text", text = "☀︎", textSize = 19, textColor = { white = 1 },
    textAlignment = "center", frame = { x = 10, y = 10, w = 28, h = 28 } })
  for i = 1, steps do
    local on = i <= M.level
    bar:appendElements({ type = "rectangle", action = "fill",
      fillColor = on and { red = 1, green = 0.8, blue = 0.3 } or { white = 1, alpha = 0.22 },
      roundedRectRadii = { xRadius = 3, yRadius = 3 },
      frame = { x = 42 + (i - 1) * (cell + gap), y = 19, w = cell, h = 8 } })
  end
  bar:show()
  if M.hide then M.hide:stop() end
  M.hide = hs.timer.doAfter(1.6, function()
    if bar then bar:delete() bar = nil end
  end)
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
  elseif M.level < steps then
    M.level = M.level + 1
    signal("-USR1")
  end
  show()
end

function M.down()
  M.level = M.level - 1
  signal(M.level == 0 and "-TERM" or "-USR2")
  show()
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
