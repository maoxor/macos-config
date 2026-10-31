# macOS settings, permissions, startup and secrets

## System settings

### Automated (declared in Nix, applied by Home Manager)
**`home-manager/macos.nix`** is the single source of truth (`targets.darwin.defaults`, user level, no sudo),
applied by `scripts/apply.sh home-manager --write` and checked against the live Mac by
`scripts/macos-defaults.sh` (also run by `verify.sh` and `doctor.sh`). It covers:

| Area | Settings |
|---|---|
| Trackpad (built-in and Magic Trackpad) | tap to click, tap to drag, no three-finger drag, three-finger tap = look up, tracking speed, scrolling speed, natural scrolling, force click off, click thresholds |
| Gestures | macOS 3- and 4-finger swipes off (per-host keys too); Mission Control and App Exposé trackpad gestures off — OmniWM owns them |
| Keyboard | key repeat 2 / delay 15, French typographic quotes; **macOS shortcuts disabled** so their keys stay free: Spotlight Cmd+Space (→ Raycast), Control+←/→ spaces, Control+↑/↓ and Control+Shift+↑/↓ Mission Control (→ OmniWM focus/move), Control+1… desktops, input-source switching, Launchpad, Notification Center |
| Dock & Mission Control | auto-hide, left, size 43, no magnification, no recent apps, Spaces never reordered, bottom-right hot corner = Quick Note |
| Windows | Stage Manager off (it fights OmniWM), widgets hidden, minimise on double-click off |
| Finder | path bar, status bar, icon view, all file extensions shown |
| Appearance | Dark mode, auto-hidden menu bar (also in full screen), clock with day of week, no interface sound effects |
| OmniWM options | `OverviewHideWorkspaceLabels`, `OverviewHideSearchBar` (patches 0001–0002) |

The Dock, Finder and menu bar restart once when these values change. Trackpad changes need a logout to reach
every app. Rollback: previous Home Manager generation (`docs/recovery.md`).

### Owned by other scripts
- Accent and highlight colours: `scripts/theme-apply.sh` (follow the wallpaper palette).
- OmniWM hotkeys, layouts, gaps, gestures: `tools/omniwm/apply-registry.py`.

### Manual (macOS gives no reliable command, or they are personal)
| Setting | Where | Reference value |
|---|---|---|
| Keyboard layout | System Settings → Keyboard → Input Sources | French (AZERTY), the shortcut registry assumes it |
| Display resolution | System Settings → Displays | "More Space" on a 16" MacBook Pro; `apply-registry.py` adapts window sizes to any resolution |
| Wallpaper | System Settings → Wallpaper | any image: the colour palette is derived from it; `theme-auto` then gives every Space the same image (`scripts/wallpaper-all-spaces.py`) |
| Screen saver | System Settings → Wallpaper → Screen Saver… → Photos → Options… → Source: folder `~/Pictures/Veille` | once: `theme-auto` keeps a copy of the current wallpaper there, so the saver shows it instead of Apple's aerial |
| Permissions | System Settings → Privacy & Security | see "Permissions" below |
| Accounts, Dock apps, iCloud, login items of your own apps | — | personal, not part of this setup |

## Permissions (TCC)
Only the user can grant a permission: System Settings > Privacy & Security > <service>.
(requires Full Disk Access for the terminal, otherwise the section is reported as not checkable).

| App | Permission | Why |
|---|---|---|
| OmniWM | Accessibility | move and resize windows |
| OmniWM | Screen Recording | Overview and swipe previews |
| Neru | Accessibility | find clickable elements |
| Hammerspoon | Accessibility | hotkeys, contexts, focus handling |
| Raycast | Accessibility | paste and snippets |

Grant nothing else (Input Monitoring is not needed). An app update that changes the code signature can revoke a grant
(`verify.sh` then reports it missing); a locally built OmniWM must be re-granted if its signing certificate changes.

**Rule:** a TCC-gated app must be launched **directly** by its LaunchAgent (`ProgramArguments`), never through a
parent script — otherwise macOS attributes the permission to the wrong process and can reset it.

## Startup (login items)
One mechanism per tool. Login items are Home Manager LaunchAgents declared in `home-manager/startup.nix`:

| Agent (`org.nix-community.home.*`) | Starts |
|---|---|
| `omniwm` | OmniWM (`open -g -a OmniWM`) |
| `hammerspoon` | Hammerspoon |
| `neru` | `neru launch`, restarted after an abnormal exit (ThrottleInterval 30 s), not after Quit |
| `stats` | Stats |
| `theme-auto` | `scripts/theme-auto.sh` when the wallpaper changes |
| `session-snapshot` | `scripts/session-snapshot.py` every minute (open Claude Code sessions, for Cmd+F5) |
| `playwright-watch` | `scripts/playwright-watch.swift` (FSEvents): each Playwright copy written under the project roots and session scratchpads is patched within ~0.7 s (`playwright-background-pages.py --files`) |
| `playwright-background-pages` | `scripts/playwright-background-pages.py` hourly, safety net: Playwright test pages (npm and Python, session scratchpads included) open behind the user's windows, in the bottom-right corner |
| `perf-journal` | `scripts/perf-journal.py` every minute: memory, CPU, GPU per process, one week kept (`docs/performance.md`) |
| `hammerspoon-guard` | `scripts/hammerspoon-guard.sh` every minute: restarts Hammerspoon above 1.5 GB while the user is idle >= 2 min (B20) |
| `memory-guard` | `scripts/memory-guard.swift` every 2 s: stops the youngest heavy job before the compressor's store fills up and the Mac panics, never an app (`docs/bugs.md` B21, `memory-guard --check`) |
| `window-journal` | `scripts/window-journal.swift` (built by `scripts/swift-tool.sh` on first run and after each change): every new window that shows over the user's work and the process that opened it, one week kept (`window-journal report`) |

**XDR boost** (brightness keys, `scripts/xdr-boost.swift`, not an agent: it runs only while on). At 100 %, F2 goes on
for 4 more steps with a level bar in Apple's glass (`NSGlassEffectView`, drawn by the tool), F1 comes back down; below 100 % the keys stay macOS's. Apple's own bar and
the Control Centre slider have no public API, so they stop at 100 %. Everyday content uses the
display's 1000 nits instead of 600. Free tools tried or rejected on 2026-10-31: BrightIntosh (no visible effect here),
FreeBright (same gamma method), MaxNit (unmaintained, unknown author); XDR is paid in Lunar and BetterDisplay.
- How: a click-through EDR window multiplies the screen, public APIs only, nothing stored, no network. macOS keeps the
  backlight and its thermal limits. Gain 1.67 at most (1000 nits, Apple's sustained full-screen rating); it follows the
  headroom macOS grants, fades in and out, and quits on a serious thermal state. Off at every login.
- Measure: `ioreg -l -w0 | grep -m1 IOMFBBrightnessLevel`, 16.16 fixed point: 600 nits off, 1600 on (the backlight cap,
  pixels are scaled down accordingly). `BrightnessMilliNits` and `InstantAmperage` do not move: do not use them.
- Limits: HDR video clips while it is on; no colour work; screenshots do not show the boost; more heat and battery wear.
- Rollback: `pkill xdr-boost`; to remove it, `git revert` the commit and apply Hammerspoon and home-manager.

A log-rotation agent also trims `~/Library/Logs/macos-config/`. Raycast uses its own "Open at Login" setting.
Do not also enable "launch at login" inside OmniWM, Hammerspoon, Neru or Stats. In System Settings > General > Login Items
the agents appear as **"sh"** (they start via `/bin/sh -c "wait4path /nix/store && exec …"`); this is expected, and so is the
"« sh » can run in the background" notification shown once when an activation adds an agent.
Plists are rewritten on every `home-manager switch`, so editing `startup.nix` takes effect on activation.
Check: `launchctl list | grep org.nix-community.home`.

## Secrets and personal data
**Never commit**: tokens, SSH/GPG keys, passwords, shell/Atuin/clipboard histories, sessions, app databases,
account identifiers, or exports of apps that store keys.

- A secret a config needs goes into an ignored file (`*.secret`, `*.env`, `secrets/`) or the keychain
  (`security add-generic-password`); the repo references only its name.
- Private exports (e.g. an encrypted Raycast `.rayconfig`) live **outside the repo**, for instance in
  `~/.local/share/macos-config-private/` (mode 700), backed up to encrypted external storage.
- Capture refuses files matching secret patterns (`SECRET_RE` in `scripts/lib.sh`) and strips identifiers from plists
  (`remote_id`, `device_id`, dates, counters, window positions). This is not a guarantee: review diffs and run
  `git diff --cached | rg -i 'token|secret|password|api.?key'` (or `gitleaks`) before committing.
- If a secret is committed: revoke/rotate it at the source first, then rewrite history.
