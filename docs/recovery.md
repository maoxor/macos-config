# Recovery and rollback

`<repo>` = your clone (path stored in `~/.config/macos-config/repo`).
Private backups: `~/.local/state/macos-power-user-deploy/backups/` (outside Git).

## 1. A tool or shortcut is stuck (keyboard works)
Escalate from lightest to strongest. None of these steps changes the configuration.

| Situation | Action |
|---|---|
| A Neru mode stays on screen | Esc |
| Hyper shortcuts dead / windows misplaced | in a terminal: `<repo>/scripts/emergency-stop.sh` |
| An app is frozen | Cmd+Option+Esc (Force Quit) |
| Neru only | `launchctl bootout gui/$(id -u)/org.nix-community.home.neru` (until next login) |
| OmniWM only | `launchctl bootout gui/$(id -u)/org.nix-community.home.omniwm; osascript -e 'quit app "OmniWM"'` (windows stay in place) |
| Hammerspoon only | `launchctl bootout gui/$(id -u)/org.nix-community.home.hammerspoon; osascript -e 'quit app "Hammerspoon"'` |
| Screen too bright, or the XDR boost misbehaves | `pkill xdr-boost` (nothing to restore: the screen is normal as soon as it ends) |
| A heavy job was stopped (exit 143 or 137) | `tail ~/Library/Logs/macos-config/memory-guard.log`, then `jobgate status`; run it again once there is room |
| The Mac froze and restarted | panic report in `/Library/Logs/DiagnosticReports/` (`.panic`); memory history: `scripts/perf-journal.py report 2` (`docs/bugs.md` B21) |

Open a terminal without shortcuts: Cmd+Space (Raycast) → "Terminal", or Finder > Applications > Utilities > Terminal.

## 2. The keyboard does not respond
- With the trackpad: Apple menu > Force Quit… (OmniWM, Hammerspoon, Neru).
- From another device, if Remote Login is enabled: SSH in and run `<repo>/scripts/emergency-stop.sh`.
- Last resort: hold the power button (unsaved work is lost).

## 3. Back to normal
`<repo>/scripts/emergency-start.sh` (reloads the agents, checks OmniWM IPC and Neru), then `scripts/verify.sh`.
Agents are also reloaded at next login. The scripts set their own `PATH` and call tools by absolute path,
so they work from Terminal.app, SSH or a shell without profile.

## 4. Rolling back a change
| Change | Rollback |
|---|---|
| App config | `scripts/apply.sh <id> --write` backs up first to `backups/apply-<date>/<original path>` and prints the restore command |
| Home Manager generation | `home-manager generations`, then `<generation path>/activate` |
| CLI package | remove it from `home-manager/home.nix`, then `home-manager switch --flake <repo>/home-manager#mac` |
| Homebrew app | quit it, remove its startup agent, `brew uninstall --cask <app>` |
| OmniWM (local build) | quit, put `backups/OmniWM-local-prev.app` back in place of the installed app, then `launchctl kickstart gui/$(id -u)/org.nix-community.home.omniwm`; config: `backups/omniwm-*/settings.toml` (see `docs/omniwm.md`) |
| macOS settings | activate the previous Home Manager generation (they are part of it), then log out and in |
| `install.sh` | files it replaced are saved under `backups/install-<date>/` |
| Lix | `/nix/nix-installer uninstall` (never `rm -rf /nix`) |

Nix generations do not back up data or permissions; keep a Time Machine (or equivalent) backup.
