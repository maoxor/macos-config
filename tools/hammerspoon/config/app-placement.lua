-- A slow app's real window can open after every placement pass at login (B23). Discord shows a splash first, then its
-- main window minutes later; it is frontmost and already known by then, so OmniWM's rule no longer applies
-- (PlacementResolver.shouldApplyWorkspaceRule) and the window lands on the active workspace, after
-- apply-window-rules.sh has finished. Each new tiled window of a process started less than RECENT seconds ago goes to
-- its workspace, once: a window the user moves later stays where they put it. Called by ws-hide.lua on each OmniWM
-- window list.
local M = {}
M.workspaces = { ["com.hnc.Discord"] = 3 }
local RECENT = 600
local CTL = os.getenv("HOME") .. "/.local/bin/omniwmctl"
local handled = {}

-- `ps -o etime=` prints [[dd-]hh:]mm:ss.
local function processAge(pid)
  local out = hs.execute("/bin/ps -o etime= -p " .. pid) or ""
  local days, rest = out:match("(%d+)%-([%d:]+)")
  local clock = rest or out:match("[%d:]+")
  if not clock then return nil end
  local seconds = 0
  for part in clock:gmatch("%d+") do seconds = seconds * 60 + tonumber(part) end
  return seconds + (tonumber(days) or 0) * 86400
end

function M.onWindows(windows)
  for _, w in ipairs(windows or {}) do
    local target = w.app and M.workspaces[w.app.bundleId]
    if target and w.id and not handled[w.id] and w.mode == "tiling" and w.workspace then
      handled[w.id] = true
      local age = w.workspace.number ~= target and w.pid and processAge(w.pid)
      if age and age < RECENT then
        hs.task.new(CTL, function()
          -- The window took focus when it opened: hand it back through ws-hide's workspace-change path.
          if wsHide then wsHide.lastAppliedId = nil; wsHide.refresh(wsHide.activeId) end
        end, { "window", "move-to-workspace", w.id, tostring(target) }):start()
      end
    end
  end
end

return M
