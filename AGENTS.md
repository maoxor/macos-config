# AGENTS.md — guide for AI agents and maintainers

This repo is the source of truth for a macOS setup (OmniWM + Ghostty + Nix/Home Manager + Homebrew +
Hammerspoon). It must stay reproducible on any Apple Silicon Mac from the repo alone. Working language:
English.

## 1. Read first
1. `README.md` — what the setup is, install, daily commands.
2. `docs/omniwm.md` — the window manager: build, workspaces, layouts, gestures, Overview, focus, rendering.
3. `docs/bugs.md` — every known bug, its cause, its fix, its check. **Do not reintroduce any of them.**
4. `docs/architecture.md` — one owner per function; `docs/shortcuts.md` — the shortcut registry.
5. `docs/macos.md` — macOS settings, permissions, login items, secrets policy.
6. `docs/performance.md` — how the Mac uses memory/CPU/GPU; measure with `scripts/perf-journal.py report` before optimising.
Authority: the real machine (checked by `scripts/verify.sh` / `scripts/doctor.sh`) > this repo.

## 2. Where to change what
| Feature | Edit | Then run |
|---|---|---|
| CLI tools, shell, prompt, Atuin | `home-manager/home.nix`, `shell.nix` | `scripts/apply.sh home-manager` (+`--write`) |
| Login agents (OmniWM, Hammerspoon, Neru, Stats, theme-auto) | `home-manager/startup.nix` | idem |
| Colours / theme | `home-manager/theme.nix`, `palette.nix` (generated), `scripts/theme-*.sh` | wallpaper change or `scripts/theme-sync.sh` |
| GUI apps | `homebrew/Brewfile` (via `brew install --cask` + `scripts/capture.sh`) | `scripts/apply.sh homebrew` |
| OmniWM behaviour (code) | a patch in `tools/omniwm/patches/` (workflow: `docs/omniwm.md` §1) | `tools/omniwm/build-local.sh` + targeted `swift test --filter` |
| OmniWM settings owned by the repo (hotkeys, gestures, layouts, gaps, Overview) | `tools/omniwm/apply-registry.py` **and** `tools/omniwm/config/settings.toml` (must agree) | quit OmniWM, `apply-registry.py <settings> --write` |
| macOS settings (gestures, trackpad, keyboard, Dock, Finder, Mission Control, disabled macOS shortcuts, OmniWM `defaults`) | `home-manager/macos.nix` | `scripts/apply.sh home-manager --write`; check: `scripts/macos-defaults.sh` |
| Hammerspoon helpers | `tools/hammerspoon/config/*.lua` (+ a row in `tools/configs.tsv` for new files) | `scripts/apply.sh hammerspoon --write` |
| Neru, Stats, Ghostty | `tools/<tool>/config/` | `scripts/apply.sh <tool>` |
| Machine-specific values | never in the repo: `identity.nix` reads `USER`/`HOME`/`MACOS_CONFIG_REPO` at build time (`--impure`, done by `scripts/apply.sh`); the clone path is in `~/.config/macos-config/repo` | `./install.sh --run identity` |
| New tool | Brewfile or `home.nix` + `tools/<id>/README.md` if it has a config (+ row in `tools/configs.tsv`) | `scripts/verify.sh` = 0 |

## 3. Invariants (keep them)
- **One owner per function** (`docs/architecture.md`): OmniWM is the only WM and gesture owner; never add
  yabai/AeroSpace/BetterTouchTool, a second launcher or clipboard manager.
- **OmniWM is upstream + patches.** Never commit inside `$OMNIWM_SRC` as the source of truth, never
  `brew upgrade` OmniWM, never ship an ad-hoc signed build (permissions are lost on each rebuild).
- **Registry = wanted state.** `theme-sync.sh` re-applies `apply-registry.py` on every wallpaper change; if
  the registry disagrees with `tools/omniwm/config/settings.toml` the user's settings get reverted (B16).
- **macOS must not own 3/4-finger swipes** (B11). Declared in `home-manager/macos.nix`.
- **Keep `focus.raiseOnMouseFocus = true`** (registry): the no-raise hover path uses private same-app
  activation records that left windows drawn inactive or doubly active (B5). Diagnose focus with the
  `focus-trace` log before changing focus code.
- **ws-hide.lua never hides apps** (B9, B10); `margin-veil.lua` stays below OmniWM's panels and swallows
  clicks (B6). Screenshots do not show OmniWM's own surfaces: verify edges by eye/photo.
- **No hardcoded user or clone paths in code** (`scripts/check.sh` enforces it). Scripts find the repo from
  their own location (`scripts/lib.sh` `REPO`); Lua uses `require("repo-path")`; Nix uses `identity.repoDir`.
- Workspace `name` = digit, label = `displayName`. Bindings are QWERTY key positions; Option alone is never bound (exceptions: Option+Tab, Option+F).
- Preview by default, back up before writing, print the rollback. No `rm -rf` on user data, no `--force`.

## 4. Safety rules on a live machine
- **Never run OmniWM's full test suite** (`swift test`): it froze the Mac. Use `--filter`.
- **Never simulate mouse/keyboard input while the user is working** (a simulated drag once landed on their
  workspace). `omniwmctl command …` and read-only queries are fine.
- Admin passwords, TCC permissions (Accessibility, Screen Recording) and keychain prompts are the user's:
  print the command or open the pane, never work around them. Do not touch SIP, SSV, boot-args, sudoers.
- Quit OmniWM before writing `settings.toml` (it rewrites the file). Restart Hammerspoon rather than
  `hs.reload()` through `hs -c`; wrap `hs -c` in `timeout`. Always `/usr/bin/log` (zsh `log` is a builtin).
- TCC-gated apps must be launched directly by a LaunchAgent, never via a parent script.
- Do not change the wallpaper as a side effect: it triggers `theme-auto` (palette + registry + commit).
- Never commit secrets, shell histories, app databases, private exports (`docs/macos.md`).

## 5. Validate a change
| Check | Command | Expect |
|---|---|---|
| Repo (offline, also CI) | `scripts/check.sh` | `All checks passed.` (syntax, ShellCheck, tracked configs, regression tests incl. registry = settings, no hardcoded paths) |
| Nix | `cd home-manager && MACOS_CONFIG_REPO=$(cd .. && pwd) nix build '.#homeConfigurations.mac.activationPackage' --no-link --impure` (or `scripts/apply.sh home-manager`, which previews) | builds |
| OmniWM patches | `tools/omniwm/build-local.sh --check` | patches apply on the pinned upstream |
| OmniWM tests | `cd $OMNIWM_SRC && swift test --filter "<Suite>"` | targeted suites pass (`docs/omniwm.md` §1) |
| Machine works | `scripts/doctor.sh` | `no failure` |
| Machine = repo | `scripts/verify.sh` | exit 0 |
| Screen edges | `tools/hammerspoon/check-margin-veil.sh --cycle` | `ok cycle` |
After a change: checks → `git diff` review → commit (imperative English, one logical change) → a line in
`CHANGELOG.md` → a `docs/bugs.md` entry if it fixed a bug (with its check).
Push to GitHub only after `scripts/check.sh` passes; never commit personal data (no user names, host names, personal apps).

## 6. Repo layout
```
install.sh  README.md  AGENTS.md  CONTRIBUTING.md  CHANGELOG.md  LICENSE.txt
home-manager/        Nix flake (CLI, shell, theme, login agents, macOS settings in macos.nix); identity.nix reads the environment
homebrew/Brewfile    apps (hand-maintained; OmniWM deliberately absent)
tools/omniwm/        UPSTREAM, patches/, build-local.sh, create-signing-cert.sh, apply-registry.py, config/
tools/hammerspoon/   config/*.lua, check-margin-veil.sh
tools/neru|stats|ghostty|raycast/   sheet (+ config/ when captured)
tools/configs.tsv    live config file <-> repo file (read by apply, capture, verify)
scripts/             doctor, verify, check, capture, apply, macos-defaults, theme-*, emergency-*, lib.sh
docs/                omniwm, bugs, architecture, shortcuts, macos, recovery; assets/
wallpapers/          local copy of the wallpaper (ignored by git)
```
nix-darwin is intentionally not used: Lix owns the Nix daemon, and Home Manager's
user-level `targets.darwin.defaults` (home-manager/macos.nix) covers every setting without sudo.
Private state of a machine (never committed): `~/.local/state/macos-power-user-deploy/` (backups, logs).

## 7. Known open items
- Niri horizontal scrolling moves the real windows through Accessibility on every frame, so heavy apps can lag
  behind lighter ones; animating captures (like the vertical swipe) is the planned fix (`docs/omniwm.md` §8).
- Tested on one Mac model (16" MacBook Pro, macOS 26.6); a clean install on a second Mac is still to be run.
