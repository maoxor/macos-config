-- Workspace-change companion for OmniWM (2026-10-09, simplified 2026-10-10).
-- On each workspace change: unhide apps (Cmd+H) that have a window on the new workspace, give
-- focus to a window of that workspace when OmniWM could not, and tell margin-veil.lua which
-- windows are visible. It no longer hides apps: hiding made workspace swipes "pop", and the
-- right-margin strip of parked windows is covered by margin-veil.lua instead (file name kept so
-- the history and docs stay valid).
local M = {}
local CTL = "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"

-- windows: OmniWM window list (from `query windows` or a windows-changed event: same objects).
local function apply(windows, activeId)
  if M.overviewOpen then return end   -- Overview open: everything stays visible, focus untouched
  local onActive = {}
  for _, w in ipairs(windows) do
    local bid = w.app and w.app.bundleId
    if bid and w.workspace and w.workspace.id == activeId then onActive[bid] = true end
  end
  local unhid = false
  for bid in pairs(onActive) do
    local app = hs.application.get(bid)
    if app and app:isHidden() then app:unhide(); unhid = true end
  end
  -- OmniWM tried to focus the workspace while its app was still hidden, so nothing got focus
  -- (focus-follows-mouse only reacts to motion). Focus the window under the pointer, else the
  -- first window of the workspace.
  local candidates = {}
  for _, w in ipairs(windows) do
    if w.workspace and w.workspace.id == activeId and (w.mode == "tiling" or w.mode == "floating") then table.insert(candidates, w) end
  end
  -- Only right after a workspace switch (or an unhide): never steal focus from a window the user
  -- chose, e.g. a floating System Settings window or an app OmniWM does not manage.
  local switched = M.lastAppliedId ~= activeId
  M.lastAppliedId = activeId
  if #candidates > 0 and (switched or unhid) then
    local front = hs.application.frontmostApplication()
    local frontBid = front and front:bundleID()
    local frontOk, frontManaged = false, false
    for _, w in ipairs(windows) do
      if w.app.bundleId == frontBid then
        frontManaged = true
        if w.workspace and w.workspace.id == activeId then frontOk = true end
      end
    end
    if unhid or (frontManaged and not frontOk) then
      local m = hs.mouse.absolutePosition()
      local h = hs.screen.mainScreen():fullFrame().h
      local px, py = m.x, h - m.y          -- OmniWM frames use a bottom-left origin
      local pick = candidates[1]
      for _, w in ipairs(candidates) do
        local f = w.frame
        if px >= f.x and px <= f.x + f.width and py >= f.y and py <= f.y + f.height then pick = w end
      end
      -- A window OmniWM already targets (e.g. picked in the Overview) wins over the pointer.
      for _, w in ipairs(candidates) do
        if w.isFocused then pick = w end
      end
      if M.focusTimer then M.focusTimer:stop() end
      M.focusTimer = hs.timer.doAfter(0.15, function()
        -- A newer switch happened meanwhile: focusing this window would pull the user back.
        if M.activeId ~= activeId then return end
        M.focusTask = hs.task.new(CTL, nil, { "window", "focus", pick.id })
        if M.focusTask then M.focusTask:start() end
      end)
    end
  end
  if marginVeil then marginVeil.update(windows, activeId) end
end

-- Debounced: moving a window (Ctrl+Shift+N) emits windows-changed, not active-workspace,
-- and unhiding emits windows-changed again (idempotent, so it settles).
-- Workspace switch: react fast (focus) with a fresh `query windows`: the focus decision needs
-- the settled state (isFocused), and a 0.05 s path was already too early. Window moves (drags
-- emit many windows-changed events): coalesce for 0.3 s and reuse the window list carried by the
-- last event (same objects as the query: no extra process).
M.fast = hs.timer.delayed.new(0.12, function() M.queryNow(M.activeId) end)
M.debounce = hs.timer.delayed.new(0.3, function()
  if M.windows then apply(M.windows, M.activeId) else M.queryNow(M.activeId) end
end)

function M.refresh(activeId)
  if activeId and activeId ~= M.activeId then
    M.activeId = activeId
    M.debounce:stop(); M.fast:start()
  else
    if activeId then M.activeId = activeId end
    M.debounce:start()
  end
end

function M.queryNow(activeId)
  if not activeId then return end
  if M.query and M.query:isRunning() then M.query:terminate() end
  M.query = hs.task.new(CTL, function(code, out)
    if code ~= 0 then return end
    local ok, data = pcall(hs.json.decode, out)
    if ok and data and data.result and data.result.payload then
      apply(data.result.payload.windows or {}, activeId)
    end
  end, { "query", "windows" })
  if M.query then M.query:start() end
end
M.refreshNow = M.queryNow   -- old name, kept for manual `hs -c` use

-- One NDJSON line: active-workspace events carry the workspace (returned), windows-changed
-- events carry the full window list (cached for the debounced path).
local function handleLine(line)
  local ok, ev = pcall(hs.json.decode, line)
  if not ok or type(ev) ~= "table" then return nil end
  local p = (ev.result and ev.result.payload) or ev.payload or ev
  if type(p) ~= "table" then return nil end
  if p.windows then M.windows = p.windows; return nil end
  return p.workspace and p.workspace.id or nil
end

-- Subscriber on OmniWM's IPC socket itself (the NDJSON protocol omniwmctl speaks, one line per event): no
-- omniwmctl process and no 5-min restart. A refused request (protocol version changed by an OmniWM update)
-- falls back to the omniwmctl task. (hs.task does not keep a streaming task's output, read in its source on
-- 2026-10-29: the multi-GB growth of Hammerspoon has another cause, see docs/bugs.md B20.)
local SUPPORT = os.getenv("HOME") .. "/Library/Application Support/com.barut.OmniWM/"
local PROTOCOL = 20   -- OmniWMIPCProtocol.version

function M.startSocket()
  local f = io.open(SUPPORT .. "ipc.sock.secret")
  local token = f and f:read("*l")
  if f then f:close() end
  if not token or token == "" then return false end
  local sock, subscribed = hs.socket.new(), false
  M.sock = sock
  sock:setCallback(function(line)
    if sock ~= M.sock then return end
    if not subscribed then
      local ok, r = pcall(hs.json.decode, line)
      if not (ok and type(r) == "table" and r.ok) then
        M.sock = nil; sock:disconnect(); M.socketRefused = true
        return M.start()
      end
      subscribed = true
    else
      M.refresh(handleLine(line))
    end
    sock:read("\n")
  end)
  sock:connect(SUPPORT .. "ipc.sock", function()
    sock:write(hs.json.encode({ authorizationToken = token, id = "hammerspoon-ws-hide", kind = "subscribe",
      version = PROTOCOL, payload = { allChannels = false, channels = { "active-workspace", "windows-changed" },
      sendInitial = true } }) .. "\n")
    sock:read("\n")
  end)
  return true
end

-- OmniWM restarted or not running yet: the socket is closed; reconnect (the initial events resynchronise).
M.socketWatch = hs.timer.doEvery(5, function()
  if M.sock and not M.sock:connected() then
    local old = M.sock
    M.sock = nil; old:disconnect(); M.start()
  end
end)

M.retryDelay = 3
function M.start()
  if M.sub and M.sub:isRunning() then return end
  -- A previous Hammerspoon instance may leave its subscriber running: stop orphans once at load
  -- (this pattern also matches the "active-workspace,windows-changed" subscriber).
  if not M.started then
    M.started = true
    hs.execute("/usr/bin/pkill -f 'omniwmctl subscribe active-workspace'")
  end
  if not M.socketRefused and M.startSocket() then return end
  M.buffer = ""
  -- --reconnect only covers a connection lost after the first one: if OmniWM is not running,
  -- omniwmctl exits at once. Retry with a backoff (3 s doubling to 60 s, reset on the first event).
  M.sub = hs.task.new(CTL, function()
    if M.recycling then M.recycling = false; M.start(); M.queryNow(M.activeId); return end
    M.restartTimer = hs.timer.doAfter(M.retryDelay, M.start)
    M.retryDelay = math.min(M.retryDelay * 2, 60)
  end, function(_, out)
    M.retryDelay = 3
    -- Output chunks are not line-aligned: keep the unfinished tail for the next chunk.
    local data = M.buffer .. (out or "")
    local last = 1
    for line, nextPos in data:gmatch("([^\n]*)\n()") do
      if line ~= "" then M.refresh(handleLine(line)) end
      last = nextPos
    end
    M.buffer = data:sub(last)
    return true
  end, { "subscribe", "active-workspace,windows-changed", "--reconnect", "--format", "ndjson" })
  if M.sub then M.sub:start() else M.restartTimer = hs.timer.doAfter(M.retryDelay, M.start) end
end

-- While OmniWM itself is frontmost (Overview open) leave focus alone; re-apply when it closes.
M.appWatcher = hs.application.watcher.new(function(_, event, app)
  local closing = M.overviewOpen and event == hs.application.watcher.activated
    and app and app:bundleID() ~= "com.barut.OmniWM"
  if closing then event = hs.application.watcher.deactivated
  elseif not app or app:bundleID() ~= "com.barut.OmniWM" then return end
  if event == hs.application.watcher.activated then
    -- OmniWM unhides managed apps itself when the Overview opens (OverviewUnhideApps). Do not
    -- walk every running app here: those calls block Hammerspoon for seconds.
    M.overviewOpen = true
  elseif event == hs.application.watcher.deactivated then
    M.overviewOpen = false
    M.lastAppliedId = nil
    M.refresh(M.activeId)
  end
end)
M.appWatcher:start()

M.start()
-- Fallback task only: restarted every 5 min, as before the socket (a query resynchronises at once).
M.recycleTimer = hs.timer.doEvery(300, function()
  if M.sub and M.sub:isRunning() then M.recycling = true; M.sub:terminate() end
end)
return M
