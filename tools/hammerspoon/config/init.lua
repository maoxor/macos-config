-- CLI « hs » pour diagnostics et tests (scripts/verify, agents).
require("hs.ipc")
-- Charge le module de contextes power-user (un seul require).
poweruser = require("poweruser")
-- Raccourcis d'applications (Cmd+E = Finder).
poweruserApps = require("poweruser-apps")
-- Restarts OmniWM and Neru when an Accessibility setting changes (prevents a system-wide freeze).
axGuard = require("ax-guard")
-- Hide apps with no window on the active OmniWM workspace (no parked-window strip in the right margin).
-- Click-through wallpaper strip over the right gap (hides parked windows without hiding apps).
marginVeil = require("margin-veil")
wsHide = require("ws-hide")
-- Cmd+F1 pastes the prompt-optimisation prompt at the cursor (clipboard restored).
promptInsert = require("prompt-insert")
-- Safari: Cmd+Left/Right = previous/next tab (outside text fields).
safariTabs = require("safari-tabs")
-- Cmd+F5: reopen apps and Claude Code sessions after a crash.
sessionRestore = require("session-restore")
-- Under lock-down, Mission Control / Spotlight on F3/F4 with a modifier do nothing.
functionKeys = require("function-keys")
-- F3: next wallpaper of ~/Pictures (the theme follows).
wallpaperCycle = require("wallpaper-cycle")
-- F4: cleaning mode, keyboard locked until a click on the banner (or 2 min).
keyboardClean = require("keyboard-clean")
-- Playwright browsers (workspace 4 by OmniWM rule) never pull the user off their workspace.
testBrowsers = require("test-browsers")
