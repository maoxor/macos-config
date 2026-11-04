-- Search Zen's open tabs and jump to one (2026-11-04). Zen has no AppleScript and Raycast's Zen extension cannot list
-- tabs, so: scripts/zen-tabs.py reads Zen's session file, a chooser filters title and address as you type, and the
-- jump goes through Zen's own tab search: Cmd+L, "% " + the address, Return (the first result is "Switch to tab").
-- Opened from anywhere by Ctrl+Space (free: macOS input-source switching is off, home-manager/macos.nix), the
-- Raycast script command "Onglets Zen", or `hs -c 'zenTabs.show()'`. Ctrl+Space again closes it.
-- The session file is rewritten a few seconds after tabs change, so a tab opened just now may be missing.
local M = {}
local SCRIPT = require("repo-path") .. "/scripts/zen-tabs.py"
local ZEN = "app.zen-browser.zen"

local function rows()
  local out = hs.execute("/usr/bin/python3 -I '" .. SCRIPT .. "' 2>/dev/null")
  local list = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local ok, t = pcall(hs.json.decode, line)
    if ok and t then
      local title = t.title or t.url
      if #title > 110 then title = title:sub(1, utf8.offset(title, 108) or 108) .. "…" end
      local host = (t.url:gsub("^%a+://", ""):gsub("[?#].*$", ""))
      local sub = host .. (t.workspace ~= "" and ("  ·  " .. t.workspace) or "") .. (t.selected and "  ·  onglet actif" or "")
      list[#list + 1] = { text = title, subText = sub, url = t.url, fullTitle = t.title }
    end
  end
  return list
end

local function switched(title)
  local w = hs.window.focusedWindow()
  local now = w and w:title() or ""
  return not title or now == title or now:find(title:sub(1, 30), 1, true) ~= nil
end

function M.switchTo(url, title)
  local zen = hs.application.get(ZEN)
  if not zen then hs.urlevent.openURLWithBundle(url, ZEN); return end
  -- Zen keeps the "Tabs" scope of its last search, so the field (chip included) is cleared first; "% " then sets the
  -- scope again, and the term is typed after a pause, since keys typed while the chip appears are lost. Enter, then
  -- Down+Enter if Zen did not switch;
  -- if it still did not, Escape closes the search instead of leaving it over the page (tested 2026-11-04).
  -- A short term: Zen re-runs its search on every key, and the full address took ~1.5 s to answer, 13 characters ~0.5 s.
  local bare = url:gsub("^%a+://", ""):gsub("[?#].*$", ""):gsub("/+$", "")
  local last = bare:match("/([^/]+)$")
  local term = (last and #last >= 6) and last:sub(1, 13) or bare
  local key = function(mods, k) hs.eventtap.keyStroke(mods, k, 0, zen) end
  zen:activate()
  hs.timer.doAfter(0.2, function()
    key({ "cmd" }, "l")
    hs.timer.doAfter(0.15, function()
      key({ "cmd" }, "a"); key({}, "delete"); key({}, "delete")
      hs.timer.doAfter(0.12, function()
        hs.eventtap.keyStrokes("% ", zen)
        hs.timer.doAfter(0.3, function()
          hs.eventtap.keyStrokes(term, zen)
          hs.timer.doAfter(0.7, function()
            key({}, "return")
            hs.timer.doAfter(0.5, function()
              if switched(title) then return end
              key({}, "down"); key({}, "return")
              hs.timer.doAfter(0.5, function()
                if switched(title) then return end
                key({}, "escape"); key({}, "escape")
                hs.alert.show("Onglet introuvable dans Zen")
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.show()
  M.chooser = M.chooser or hs.chooser.new(function(choice)
    if choice and choice.url ~= "" then M.switchTo(choice.url, choice.fullTitle) end
  end)
  M.chooser:placeholderText("Onglet Zen…"):searchSubText(true):rows(12)
  local list = rows()
  M.chooser:choices(#list > 0 and list or { { text = "Aucun onglet trouvé", subText = "Zen n'a pas encore écrit sa session", url = "" } })
  M.chooser:show()
end

M.hotkey = hs.hotkey.bind({ "ctrl" }, "space", function()
  if M.chooser and M.chooser:isVisible() then M.chooser:hide() else M.show() end
end)

return M
