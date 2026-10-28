# Architecture: who does what

## Layers
```
macOS
├── Package managers
│   ├── Lix (Nix daemon) ── Home Manager (home-manager/) ── CLI tools, shell, theme, login agents
│   └── Homebrew ── GUI apps (homebrew/Brewfile)
├── Interaction
│   ├── OmniWM ............ windows (Dwindle on W1, Niri elsewhere), workspaces, 3/4-finger gestures
│   ├── Hammerspoon ....... contexts (Hyper+P), ax-guard, margin-veil → omniwmctl (IPC)
│   ├── Neru .............. keyboard navigation (Hyper+N/G/S)
│   └── Raycast ........... launcher (Cmd+Space), clipboard history
└── Apps: Ghostty, Stats, and your apps
```
OmniWM details: `docs/omniwm.md`. Shortcuts: `docs/shortcuts.md`. macOS settings: `docs/macos.md`.

## Responsibilities (one owner per function)
| Function | Owner | Must NOT handle it |
|---|---|---|
| CLI installation | Home Manager | Homebrew |
| GUI app installation | Homebrew | Nix |
| Nix daemon | Lix installer | nix-darwin (not used) |
| Shell, prompt, PATH | Home Manager (`shell.nix`) | hand edits of `~/.zshrc` |
| Ctrl-R history | Atuin (local) | fzf (its Ctrl-R is disabled) |
| Window placement / tiling | OmniWM, local build | Raycast window commands, Hammerspoon `hs.window`, macOS edge tiling |
| Workspaces | OmniWM (Focus, Web, Messages, Atelier, 5–9) | macOS Spaces (a single native Space) |
| App → workspace | OmniWM rules | Hammerspoon |
| Playwright test browsers (Claude Code experiments) | OmniWM rules → W4 Atelier; `test-browsers.lua` sends later windows there and gives focus back | — |
| Contexts (workspace + resources) | Hammerspoon `poweruser.lua` | — |
| Window borders / workspace bar | OmniWM, disabled by choice | JankyBorders, SketchyBar |
| Keyboard navigation (hints) | Neru | Raycast |
| Launcher | Raycast (Cmd+Space) | Spotlight shortcut (disabled) |
| Clipboard history | Raycast | OmniWM (`clipboard.historyEnabled = false`) |
| 2-finger gestures | macOS / apps | OmniWM |
| 3-finger and 4-finger-up gestures | OmniWM | macOS (disabled in `home-manager/macos.nix`) |
| Theme / palette | Stylix, palette generated from the wallpaper (`scripts/theme-auto.sh` → `home-manager/palette.nix`); `scripts/theme-apply.sh` → Neru, macOS accent, OmniWM | hand-edited colors |
| macOS preferences | Home Manager `home-manager/macos.nix` (checked by `scripts/macos-defaults.sh`) | nix-darwin, hand-run `defaults write` |
| App startup | Home Manager LaunchAgents (`home-manager/startup.nix`); Raycast: its own | apps' internal "open at login" |

## Decisions
- **nix-darwin is intentionally not used.** Lix owns the Nix daemon; macOS settings are applied (and reversible)
  through `home-manager/macos.nix` (checked by `scripts/macos-defaults.sh`).
- **One tool per function** (windows, clipboard, gestures, packages); nothing is installed "just in case".
- **OmniWM** is the only window manager, built locally from a pinned upstream commit plus patches.
  Rejected alternatives: AeroSpace, yabai, Paneru.
- **Hyper = Ctrl+Option+Cmd** without Caps Lock remap (no Karabiner).
- **Raycast** is the single launcher and clipboard history (no Maccy); OmniWM's built-in bar and borders stay off
  (no SketchyBar/JankyBorders).
- **Home Manager is one-way** (repo → machine); generated files are never captured back.
- **TCC-gated apps are launched directly** by their LaunchAgent (see `docs/macos.md`).

## Machine ↔ repo
- `verify.sh [--hm]` compares machine and repo for what this setup manages (exit 1 on drift); `doctor.sh` checks that everything works.
- `capture.sh` copies the closed list in `tools/configs.tsv` into the repo and shows diffs; `capture.sh --accept` writes them (refused over uncommitted changes; secret patterns refused).
- `apply.sh <id>` previews, `--write` applies repo → machine after a backup in `backups/apply-<date>/`.

## Key flows
- **Hyper+P → context**: Hammerspoon runs `omniwmctl workspace focus-name <Workspace>`; if that fails nothing opens;
  otherwise it opens the resources. Resource apps need an OmniWM rule for their workspace.
- **Wallpaper → theme**: a LaunchAgent watches the wallpaper index; `scripts/theme-auto.sh` regenerates the palette
  and applies it (Home Manager, Neru, OmniWM, Ghostty reload).
- **Shell**: `/bin/zsh` reads `~/.zshenv` (HM variables), `~/.zprofile` (brew shellenv), `~/.zshrc` (starship, zoxide,
  atuin, fzf); `/etc/zshrc` (Lix) adds Nix.

## Manual checks
After install or a major change, verify by hand:
1. AZERTY typing: `@ | \ { } [ ] ~`, `é è à ç ù`, dead keys `^`/`¨` + `e`, Option+Space — characters appear, no window moves.
2. Gestures: 3 fingers left/right scrolls Niri columns (nothing on workspace 1); 2 fingers scrolls content; 3 fingers up/down switches workspace; 4 fingers up opens the OmniWM Overview.
3. Ctrl+1…4 and Ctrl+Shift+digit move between/send to workspaces; Option+Tab returns to the previous window.
4. Hyper+O, Hyper+P (contexts), Hyper+N (Neru hints) all respond.
5. After sleep/wake and after a logout/login, the above still work (`scripts/doctor.sh`).

## Known limits
- A Finder window cannot be assigned by path.
- Simulated arrow keystrokes must carry the fn flag to trigger OmniWM (real keys do).
- Apps with a minimum width (Safari, Finder) overflow when too many windows share a workspace.
