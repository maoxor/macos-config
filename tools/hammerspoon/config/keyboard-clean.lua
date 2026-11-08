-- F4: cleaning mode. Every key is swallowed (letters, modifiers, brightness, volume, media) while the
-- trackpad keeps working; a click on the card, or 2 minutes, ends it. Touch ID / power cannot be blocked.
-- Bound on F4 (keycode 118, fn) and on the Spotlight / Launchpad codes the bare F4 sends (177, 131).
local M = {}
local DURATION = 120
local types = hs.eventtap.event.types
local f4 = { [118] = true, [177] = true, [131] = true }

-- The card is keyboard-clean.html in a transparent webview: CSS animations on transform / opacity run on the
-- GPU compositor, so the entrance costs no CPU and once it is over only the time bar moves. The image is
-- ~/.config/macos-config/keyboard-clean.jpg (or .png): personal, kept out of the repo; a pumpkin otherwise.
local W, H = 520, 680
local DIR = os.getenv("HOME") .. "/.config/macos-config/keyboard-clean."
local PAGE = hs.configdir .. "/keyboard-clean.html"

local function imageURI()
  for _, ext in ipairs({ "jpg", "png" }) do
    local img = hs.fs.attributes(DIR .. ext) and hs.image.imageFromPath(DIR .. ext)
    if img then return img:encodeAsURLString(false, "JPEG") end
  end
  return "'data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22>" ..
         "<text x=%2250%22 y=%2262%22 font-size=%2250%22 text-anchor=%22middle%22>🎃</text></svg>'"
end

function M.show() -- also a preview without blocking the keyboard
  if M.view then M.view:delete(); M.view = nil end -- never two cards: a leftover one would stay forever
  local f = io.open(PAGE); local html = f:read("a"); f:close()
  html = html:gsub("{{IMG}}", function() return imageURI() end):gsub("{{DURATION}}", tostring(DURATION))
  local s = hs.screen.mainScreen():frame()
  M.content = hs.webview.usercontent.new("kc"):setCallback(function() M.stop() end)
  M.view = hs.webview.new({ x = s.x + (s.w - W) / 2, y = s.y + (s.h - H) / 2, w = W, h = H }, {}, M.content)
  M.view:transparent(true):level(hs.canvas.windowLevels.screenSaver)
        :behavior(hs.drawing.windowBehaviors.canJoinAllSpaces | hs.drawing.windowBehaviors.stationary)
        :allowTextEntry(false):html(html):show()
end

function M.stop()
  if M.block then M.block:stop(); M.block = nil end
  if M.timer then M.timer:stop(); M.timer = nil end
  if M.view then
    local v = M.view; M.view, M.content = nil, nil
    v:evaluateJavaScript("leave()")
    -- Keep a reference to the timer: an unreferenced hs.timer can be garbage-collected before it fires, which left
    -- the transparent card on screen, swallowing clicks in the middle of every app (B25).
    M.leave = hs.timer.doAfter(0.3, function() v:delete(); M.leave = nil end)
  end
end

function M.start()
  if M.block then return end
  M.block = hs.eventtap.new({ types.keyDown, types.keyUp, types.flagsChanged, types.systemDefined }, function(e)
    if e:getType() == types.systemDefined then return next(e:systemKey()) ~= nil end -- media keys only
    return true
  end)
  M.block:start()
  M.show()
  M.timer = hs.timer.doAfter(DURATION + 0.9, M.stop) -- the countdown starts after the 0.9 s entrance
end

M.trigger = hs.eventtap.new({ types.keyDown }, function(e)
  if M.block or not f4[e:getKeyCode()] then return false end
  local fl = e:getFlags()
  if fl.cmd or fl.alt or fl.ctrl or fl.shift then return false end
  -- Start once F4 and any modifier are released: a swallowed key-up would leave them pressed for the apps.
  hs.timer.waitUntil(function() return next(hs.eventtap.checkKeyboardModifiers()) == nil end,
                     function() hs.timer.doAfter(0.15, M.start) end, 0.05)
  return true
end)
M.trigger:start()

return M
