# Changelog

All notable changes. Format: newest first; each entry says what changed and how to roll it back when that
is not a plain `git revert`.

## Unreleased
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
