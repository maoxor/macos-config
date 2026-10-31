-- Cmd+F3: XDR brightness boost on / off through BrightIntosh's CLI (tools/brightintosh/README.md), starting the app if
-- needed. Its own Cmd+Option+B never reached it here (2026-10-31), and three keys is one too many anyway.
local M = {}
local app = "/Applications/BrightIntosh.app"
local bin = app .. "/Contents/MacOS/BrightIntosh"
local id = "de.brightintosh.app"

local function cli(command, done)
  hs.task.new(bin, done, { "cli", command }):start()
end

local function report()
  cli("status", function(_, out)
    hs.alert.show((out or ""):find("Enabled") and "Luminosité boostée" or "Luminosité normale")
  end)
end

function M.toggle()
  if not hs.fs.attributes(bin) then hs.alert.show("BrightIntosh n'est pas installé") return end
  if hs.application.get(id) then
    cli("toggle", report)
  else
    cli("enable", function()
      hs.task.new("/usr/bin/open", report, { "-g", "-a", app }):start()
    end)
  end
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
