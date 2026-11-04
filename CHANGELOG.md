# Changelog

All notable changes. Format: newest first; each entry says what changed and how to roll it back when that
is not a plain `git revert`.

## Unreleased
- Zen tab search is now a native Raycast list (local extension `tools/raycast/zen-tabs`: favicons, site, workspace,
  actions), opened by Ctrl+Space; it replaces the Hammerspoon chooser and the script command.
- Ctrl+Space: Zen tab search from anywhere (the same chooser as Raycast "Onglets Zen"). Rollback: `git revert`, apply
  Hammerspoon.
- Cmd+F2: the XAU/USD prompt replaced by the user's new version, in Markdown (# headings, * lists, the orders table),
  so its structure survives the paste. Rollback: `git revert`, apply Hammerspoon, restart it.
- Zen tab search: Raycast "Onglets Zen" (alias z) opens a chooser of Zen's open tabs (`scripts/zen-tabs.py` reads
  the session file; Zen has no AppleScript) and Enter jumps to the tab through Zen's own tab search (`zen-tabs.lua`).
- Top bar, geek edition: app icons per workspace (animated current chip), CPU graph, GPU, network speed, popups (busiest
  processes with memory-guard, month calendar). Cmd+Shift+F in browsers = OmniWM fullscreen under the bar (native full
  screen hid the bar and showed the macOS menu). Rollback: `git revert`, apply home-manager and Hammerspoon.
- Top bar: SketchyBar replaces the macOS menu bar (auto-hidden, now in full screen too), "pills" style chosen from six
  mockups; workspaces live from OmniWM, focused window, CPU, memory, sound, Wi-Fi, battery, clock; colours follow the
  wallpaper. Rollback: drop `./sketchybar.nix` from `home.nix`, `scripts/apply.sh home-manager --write`.
- Palette, warm wallpaper: dark frosted background (#1C1D20, cool hue, opacity 0.78 with blur) instead of the
  flat near-black, the user's choice.
- Hover focus slow between Ghostty windows (B24): OmniWM patch 0033 (below) and a Ghostty restart; raising on a
  worker thread was tried and rejected (Ghostty then kept the old window key).
- OmniWM patch 0033, hover focus: the re-evaluation after the debounce could drop silently and a hover denied during
  an app switch was never retried, so the window under a stopped pointer waited for the next mouse move; debounce
  0.1 s → 0.04 s. Rollback: delete the patch, `tools/omniwm/build-local.sh` (previous build also kept in
  `~/.local/state/macos-power-user-deploy/backups/OmniWM-local-prev.app`).
- Palette, warm wallpaper: accents in reds, crimson, rose and greys (muted green and gold kept for success and warnings)
  instead of the fixed rainbow, which clashed with a red-on-black image (`WARM_ROLES` in `palette-from-image.py`).
- Palette: a warm wallpaper (red, orange, yellow) gets a neutral charcoal background (saturation 0.03; 0.12 still read
  brown), a neutral text and terminals at opacity 0.95 (`palette-from-image.py`); the red fractal had turned every window maroon with pink text. Its saved palette
  was regenerated. Rollback: `git revert`, `scripts/theme-sync.sh`.
- Upscayl (free, offline Real-ESRGAN upscaler) added to the Brewfile; its CLI made the current landscape wallpaper
  (x4, high-fidelity model, via jobgate). Rollback: `brew uninstall --cask upscayl`, drop the line.
- Borders removed at the user's request: JankyBorders off (`enable = false`, settings kept), so Raycast's ring is gone too
  (`raycast-dim.lua` draws it only while bordersrc exists); the Raycast backdrop stays. Back: `enable = true`, apply
  home-manager.
- Focused-window border: fixed strong violet #B026FF, 6 pt (user's choice), and Raycast's panel ringed the same way by
  `raycast-dim.lua` (reads colour and width from bordersrc); not the wallpaper accent any more; theme-apply.sh no longer
  recolours it. Rollback: `git revert`, `scripts/apply.sh home-manager --write`.
- Raycast set up on this Mac: script folder `tools/raycast/script-commands` added, aliases `v f m s e t` given, Store
  extensions "Browser Tabs" and "Zen Browser"; README names the real commands (Search Menu Bar Items; Browser Tabs skips
  Zen, where `%` in the address bar searches tabs). Zen imported Safari's bookmarks and history, not its passwords.
- Focused-window border: JankyBorders replaces OmniWM's (judged poor): 4 pt, palette accent, each window's real corner
  radius; Home Manager `services.jankyborders` (`home-manager/borders.nix`), recoloured live by `theme-apply.sh`.
  Rollback: drop `./borders.nix` from `home.nix` imports, `scripts/apply.sh home-manager --write`.
- Browsers: Zen becomes the main browser (W2; `tools/zen/apply-profile.sh` sets `user.js` and adds uBlock Origin and Auto
  Tab Discard: tabs idle 10 min are unloaded), Helium the development browser (W4); Safari kept. Cmd+←/→ switch tabs in
  all three; Cmd+F5 also reopens Zen. OmniWM draws a 2 pt border in the palette accent around the focused window.
  Rollback: `git revert`, copy the backed-up `settings.toml` (hot-reloaded), apply Hammerspoon, restart it,
  `brew uninstall --cask zen helium-browser`.
- Raycast: the screen behind its launcher is dimmed (`raycast-dim.lua`; Raycast has no such setting; window-journal
  ignores this backdrop); script commands tracked in `tools/raycast/script-commands/` (find a window, Mac status, next
  wallpaper, keyboard cleaning, session restore) and a one-hotkey-then-alias logic (`tools/raycast/README.md`).
  Rollback: `git revert`, apply Hammerspoon, restart it, `launchctl kickstart -k gui/$UID/org.nix-community.home.window-journal`.
- Cmd+F2: the XAU/USD prompt replaced by the user's new version (quotes and candles first from the Massive
  XAUUSD Live connector). Rollback: `git revert`, apply Hammerspoon, restart it.
- Reopening after a shutdown (B23): Cmd+F5 needs a second press within 5 s, the first only lists what would reopen;
  Discord's late main window goes to workspace 3 (`app-placement.lua`); an ended Claude Code session loses its stale
  Artifact comment monitors, so resuming it no longer prints one line per artifact (`claude_monitors.py`);
  `boot-history.log` keeps what ended and started each boot. Rollback: `git revert`, apply Hammerspoon, restart it.
- `hs -c` no longer hangs in the repo scripts: it waits on an open stdin, hence `</dev/null` (restart-hammerspoon looped,
  doctor reported Hammerspoon silent while it was fine). doctor watches the memory guard and the XDR boost; check.sh
  compiles the Swift tools on macOS; `perf-journal report` shows the compressor's store; README, AGENTS and recovery
  updated (31 OmniWM patches, not 27).
- XDR boost (brightness keys, past 100 %; `scripts/xdr-boost.swift`): our own tool, public APIs only, gain capped at
  1000 nits. BrightIntosh
  tried and removed. Rollback: `git revert`, then apply Hammerspoon and home-manager.
- Kernel panics from memory exhaustion prevented (B21): jobgate uses the larger of `--mem` and a job's real peaks and
  admits nothing once the compressor's store is 50 % full; the new `memory-guard` agent reads that store every 2 s and
  stops the youngest job at 70 %, never an app. Rollback: `git revert`, then `./scripts/apply.sh home-manager --write`.
- Cmd+F2 (XAU/USD prompt): quotes and H4/H1/M15/M5 candles come first from the TwelveData-XAUUSD-Live
  connector, TradingView / Investing.com only as a fallback. Rollback: `git revert`, apply Hammerspoon, restart it.
- Upstream contributions to OmniWM: OmniNull/OmniWM#1056 (preview captures recover when ScreenCaptureKit stops
  answering: start and window-discovery timeouts, the upstream form of patch 0032) and OmniNull/OmniWM#1055
  (a diagonal swipe start settles its direction: patch 0008, plus the swipe sample kept while waiting).
  Building upstream main needs `swiftly` (Brewfile) and the snapshot in its `.swift-version`.
- OmniWM patch 0028 removed: it guarded a failure reason OmniWM never produces (`cannotComplete` is mapped to
  `.staleElement`), so it never changed anything. Rollback: `git revert`.
- OmniWM patch 0032: workspace swipes keep their animation after macOS' capture service (replayd) crashes: a
  capture start with no answer after 3 s is dropped (B7). Rollback: remove the patch, rebuild OmniWM.
- OmniWM patch 0031: vertical workspace swipes no longer show another tab first (stale snapshot or retained frame);
  see B7. Rollback: remove the patch, rebuild OmniWM.
- CI: `actions/checkout@v7` (Node 24; v4 runs on the deprecated Node 20).
- CI green again (it failed from 2026-10-29 13:47): `macstat.py` imports on Linux, so jobgate's self-test runs on the
  runner. `hammerspoon-guard` agent: restarts Hammerspoon above 1.5 GB while the
  user is away (B20). Rollback: remove the agent from `home-manager/startup.nix` and re-apply.
- OmniWM patch 0030: a Chrome, Edge or Brave launched by a driver (`--remote-debugging-pipe` for Playwright
  `channel: "chrome"`, `--remote-debugging-port=0` / `--enable-automation` for Puppeteer and Selenium) follows the Chrome for Testing rules (workspace 4) instead of being tiled
  over the user's workspace; `test-browsers.lua` gives the keyboard back from it and moves force-floated Safari
  windows on each OmniWM window event (no query every 2 s). Rollback: remove the patch, rebuild OmniWM; `git revert`.
- Hammerspoon memory (B20): cause found, agents' `hs -c` window captures (`saveToFile` autoreleases ~500 MB per
  capture, never drained in a background app); GC every 10 s; `scripts/restart-hammerspoon.sh` restarts it reliably.
- `playwright-watch` agent (FSEvents): every Playwright copy is patched ~0.7 s after it is written instead of up to
  5 minutes later (sessions test right after installing); the full walk becomes hourly. `scripts/swift-tool.sh`
  builds and runs the Swift helpers. Rollback: remove the agent from `home-manager/startup.nix`, set the walk back
  to 300 s, re-apply.
- `verify.sh`: an outdated cask is reported ("newer versions available"), no longer a drift: apply installs with
  `--no-upgrade` and upgrades stay a decision. `AGENTS.md`: the Nix build check needs `MACOS_CONFIG_REPO` and
  `--impure`.
- `ws-hide` subscribes on OmniWM's IPC socket directly (no `omniwmctl subscribe` process, no 5-min restart;
  falls back to it if the request is refused). The earlier explanation of Hammerspoon's memory growth
  ("hs.task keeps the whole output") was wrong; the growth is still open (B20). The margin veil stretches its
  wallpaper slice with `scaleToFit` (`scaleToFill` is not an hs.canvas value: an error on every build).
  Rollback: `git revert` and `scripts/apply.sh hammerspoon --write`, then restart Hammerspoon.
- Window journal: the `window-journal` agent records every new window that shows over the user's work, for how
  long, and the process (project) that opened it; `window-journal report [hours]` (B19). Rollback: remove the
  agent and the `.local/bin/window-journal` entry from `home-manager/startup.nix` and re-apply.
- Playwright test pages are born in the bottom-right corner as well as behind the user's windows: Ghostty is
  translucent, so a 1200x1257 page window behind the terminals still showed through for 20-85 ms (Chrome keeps
  40 x 41 pt of a window on screen, OmniWM parks it in ~20 ms). The patch now also covers Python Playwright, the
  Codex runtime and the Claude Code session scratchpads (101 copies instead of 22) and runs every 5 minutes instead
  of hourly. Rollback: `scripts/playwright-background-pages.py --undo`.
- Home Manager installs gitleaks (the projects' pre-commit hooks refused every commit without it).
- `docs/performance.md` §6: best parallelism measured (RuboCop: the default 18 workers is optimal, ×7.8; replays
  with the shared cache: ×7.1 at 12 at once).
- `docs/performance.md` §6: measured structural wins (shared mmap'd cache of preprocessed data: a replay 408 → 147 s,
  peak 8.4 → 0.23 GB, identical outputs).
- `jobgate` (scripts/jobgate.py, on PATH): heavy jobs start as soon as the memory they need is really free (kernel
  free memory and real footprints, learnt needs), PyTorch MPS jobs get watermarks sized to that free memory, and
  concurrency is reduced only while the Mac thrashes (youngest job paused, oldest resumed first). Compatible with
  the projects' `heavy.py` lock. `scripts/macstat.py` holds the measures shared with `perf-journal.py`.
  Rollback: remove the `.local/bin/jobgate` entry from `home-manager/startup.nix`; jobs keep working without it.
- The projects' `heavy.py` / `lourd.py` copies (12) delegate to jobgate through `scripts/heavy-compat.py` (same
  command line and lock); jobgate keeps their watchdog as a last resort (memory critical for 20 s: the youngest
  job stops with exit 75). Rollback: `~/.local/state/macos-power-user-deploy/backups/jobgate-migration-*/ROLLBACK.txt`.
- Performance journal: the `perf-journal` agent samples memory pressure, wired/compressor/swap, CPU user/system,
  GPU and the top processes by real footprint every minute (8 days kept; `scripts/perf-journal.py report`).
  `docs/performance.md` records what was measured, what is worth changing and what was rejected. Rollback:
  remove the agent from `home-manager/startup.nix` and re-apply.
- `restore-session.py` and `session-restore.lua` find the repo from the clone instead of a fixed path
  (`scripts/check.sh` failed on it).
- Browser tests of Claude Code sessions no longer show over the user's windows: Playwright pages open behind
  them (`scripts/playwright-background-pages.py`, hourly agent; rollback: `--undo`), OmniWM rules send the
  test browsers to workspace 4 and patch 0029 keeps their later windows there without switching the view;
  `test-browsers.lua` gives the keyboard back and moves force-floated Safari windows to workspace 4.
- Hammerspoon memory (3.5–4.6 GB before, ~30 MB now): the margin veil shows a wallpaper slice cut by `sips`
  (decoding the full picture left ~500 MB per rebuild); `ws-hide` restarts its OmniWM subscriber every 5 min
  (`hs.task` keeps the whole output of a running task); a 5 min GC; Hammerspoon starts in 0.7 s instead of 23 s
  (no `hs.window.filter`, shortcuts load first).
- Wallpaper: every Space gets the current wallpaper (`scripts/wallpaper-all-spaces.py`, backup
  `Index.plist.bak`); the screen saver shows it through `~/Pictures/Veille` (one manual setting, `docs/macos.md`).
- Cmd+F5 session restore: an empty snapshot at shutdown keeps the last list; a restored account-2 session no
  longer leaves `CLAUDE_CONFIG_DIR` exported in its shell.
- Shortcuts: Cmd+F2 pastes the XAU/USD analysis prompt; F3 next wallpaper; F4 keyboard cleaning mode.
- Audio files open in QuickTime Player, not Apple Music (`swift scripts/default-audio-app.swift`; rollback:
  Finder > Get Info > Open with > Music > Change All).
- `/delete` (Claude Code skill, both accounts) ends the current session and moves it to the Trash; `claude-rm`
  lists closed sessions and moves the
  chosen ones to the Trash; Claude Code has no built-in command for one session.
- OmniWM patch 0028: Option+F works again after leaving macOS fullscreen (an unanswered size write is no
  longer learned as a minimum size).
- Theme follows the wallpaper again when it is set for one display (`theme-auto.sh` fingerprints the whole
  wallpaper index); Cmd+F5 restores Claude Code sessions; optional lock-down (`profile.local.nix`).
- OmniWM patches 0020–0027: fullscreen exit keeps the column width and its gaps; scroll animation stops
  re-writing window sizes; workspace restore survives a quit during startup and a locked screen; leaving a
  full-width Niri column takes the same gesture as a half-width one; a reproducible scroll bench. The column-scroll
  image proxy was removed (rejected visually).
- Option+F = Niri full width; Hammerspoon: Cmd+F1 pastes the prompt-optimisation prompt, Cmd+←/→ switch Safari
  tabs outside text fields.
- `scripts/doctor.sh` fails when `com.apple.synapse.contentlinkingd` is disabled: an old debloat had disabled it
  and Safari froze ~500 ms during scrolls (`docs/bugs.md` B18). Re-enable: see B18.
- `tools/omniwm/bench`: scroll measurement tools (WindowServer polling, 120 fps pixel capture, test app).
- `claude2` alias: Claude Code with a second account (`CLAUDE_CONFIG_DIR=~/.claude-2`); `claude` unchanged.

## 1.1.0
- macOS settings declared in Nix (`home-manager/macos.nix`): trackpad, gestures, keyboard and the macOS
  shortcuts disabled for OmniWM/Raycast, Dock, Mission Control, Finder, Stage Manager, appearance;
  `scripts/macos-defaults.sh` now checks them against the live Mac.
- Control+arrows = focus and Control+Shift+arrows = move in all four directions (macOS Mission Control chords
  disabled).
- `identity.nix` reads user, home and clone from the environment: a clean clone builds with no personal value.
- OmniWM patches 0008–0017: bug fixes from earlier local builds (diagonal swipe start, swipe sensitivity,
  wallpaper cache, Secure Input panel, System Settings focus, Overview captures) and focus reliability
  (macOS-checked "already focused", debounce trailing edge, `focus-trace` log); `raiseOnMouseFocus = true`.
- OmniWM patches 0018–0019: on a workspace switch the window landing under the pointer gets focus (not the
  workspace's remembered window); also after a Niri scroll.

## 1.0.0 — first public release
- Guided installation (`install.sh`), diagnostic (`scripts/doctor.sh`), drift check (`scripts/verify.sh`),
  declarative macOS settings with a restore script (`scripts/macos-defaults.sh`).
- OmniWM built from a pinned upstream commit plus 7 patches (Overview without labels/search bar, clean
  screen edges, sharp and colour-accurate workspace swipes, no Niri column overlap during swipes), signed
  with a local certificate so macOS permissions survive rebuilds.
- Home Manager flake: CLI tools, zsh + Starship + Atuin, Ghostty and Stylix theme generated from the
  wallpaper, login agents. No machine-specific value in the code (`identity.nix` written by the installer).
- Hammerspoon helpers: contexts, refocus after workspace switches, screen-edge veil, Accessibility guard.
- Documentation: README, `AGENTS.md`, OmniWM reference, shortcuts, architecture, macOS, recovery, and a
  catalogue of the bugs met while building this setup with their causes and checks (`docs/bugs.md`).
