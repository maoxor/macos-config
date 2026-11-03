-- Browsers: Cmd+Left / Cmd+Right = previous / next tab (like Cmd+1…9 jumps to a tab), the same keys in Safari, Zen
-- and Helium. Inside a text field (address bar, web forms) the keys keep their macOS meaning: start / end of line.
-- Each browser gets its own "next tab" chord: Zen's Ctrl+Tab follows the recently used order (tools/zen/user.js),
-- so Zen and Helium use Cmd+Option+arrow, which always means the neighbouring tab there.
local M = {}
local SAFARI = { prev = { { "ctrl", "shift" }, "tab" }, next = { { "ctrl" }, "tab" } }
local ARROWS = { prev = { { "cmd", "alt" }, "left" }, next = { { "cmd", "alt" }, "right" } }
M.browsers = { ["com.apple.Safari"] = SAFARI, ["app.zen-browser.zen"] = ARROWS, ["net.imput.helium"] = ARROWS }

local textRoles = { AXTextField = true, AXTextArea = true, AXComboBox = true, AXSearchField = true }

local function inTextField()
  local ok, el = pcall(function() return hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement") end)
  if not ok or not el then return false end
  local role = el:attributeValue("AXRole")
  if textRoles[role] then return true end
  return el:attributeValue("AXEditable") == true
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local code = e:getKeyCode()
  if code ~= hs.keycodes.map.left and code ~= hs.keycodes.map.right then return false end
  local f = e:getFlags()
  if not (f.cmd and not f.alt and not f.ctrl and not f.shift) then return false end
  local app = hs.application.frontmostApplication()
  local keys = app and M.browsers[app:bundleID()]
  if not keys or inTextField() then return false end
  local k = code == hs.keycodes.map.left and keys.prev or keys.next
  hs.eventtap.keyStroke(k[1], k[2], 0)
  return true
end)
M.tap:start()

return M
