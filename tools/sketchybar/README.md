# SketchyBar

The top bar, in place of the macOS menu bar (which stays auto-hidden, full screen included). "Pills" style chosen on
2026-11-04 from six mockups: one glass pill per group, in the 39 pt band of the menu bar on either side of the
222 pt notch; windows do not move.

- **Install and start:** Home Manager (`home-manager/sketchybar.nix`): the package, the launchd agent `sketchybar`,
  JetBrainsMono Nerd Font for the icons, jq for the scripts.
- **Config:** this folder (`sketchybarrc`, `plugins/`), copied as is. `colors.sh` is generated from the wallpaper
  palette; `scripts/theme-apply.sh` reloads the bar after a theme change.
- **Content:** workspaces 1-4 (current = accent, with windows = text, empty = grey; a click switches), focused window
  with its app icon, CPU share and memory in use, sound, Wi-Fi, battery (red at 20 % or less, green on power), date
  and time in French.
- **Live data:** `omniwmctl watch focus,active-workspace,windows-changed` fires the custom event `omniwm_update`
  (started by `sketchybarrc`, replaced on reload).
- **Above the macOS menu bar:** `topmost=on` (window level 25; the menu bar is 24). The menu bar still slides in if
  the pointer touches the very top edge; the pills stay over it.
- **Check:** `sketchybar --query bar`, `launchctl list | grep sketchybar`. Reload: `sketchybar --reload`.
- **Remove:** drop `./sketchybar.nix` from `home-manager/home.nix` imports, `scripts/apply.sh home-manager --write`.
