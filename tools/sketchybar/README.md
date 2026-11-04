# SketchyBar

The top bar, in place of the macOS menu bar (which stays auto-hidden, full screen included). "Pills" style chosen on
2026-11-04 from six mockups: one glass pill per group, in the 39 pt band of the menu bar on either side of the
222 pt notch; windows do not move.

- **Install and start:** Home Manager (`home-manager/sketchybar.nix`): the package, the launchd agent `sketchybar`,
  JetBrainsMono Nerd Font for the icons, jq for the scripts.
- **Config:** this folder (`sketchybarrc`, `plugins/`), copied as is. `colors.sh` is generated from the wallpaper
  palette; `scripts/theme-apply.sh` reloads the bar after a theme change.
- **Content (geek edition, 2026-11-04):** workspaces 1-4 with the app icons of their windows (sketchybar-app-font;
  current = accent chip, animated; hover highlight; a click switches), focused window with its app icon; CPU graph
  and share (red from 70 %), GPU use (IOAccelerator), memory in use, network down/up on the default interface;
  sound, Wi-Fi, battery (red at 20 % or less, green on power); date and time in French.
- **Popups:** click CPU = the five busiest processes, the memory-guard margin and the load average; click the clock =
  this month from Monday, this week in green. Leaving the bar closes them.
- **Full screen:** macOS native full screen moves the window to its own Space, where SketchyBar is not drawn (the band
  turns black and the macOS menu bar slides in). Cmd+Shift+F in Zen, Helium and Safari therefore runs OmniWM's
  fullscreen instead (`tools/hammerspoon/config/browser-fullscreen.lua`): the window fills the screen under the bar.
- **Live data:** `omniwmctl watch focus,active-workspace,windows-changed` fires the custom event `omniwm_update`
  (started by `sketchybarrc`, replaced on reload).
- **Above the macOS menu bar:** `topmost=on` (window level 25; the menu bar is 24). The menu bar still slides in if
  the pointer touches the very top edge; the pills stay over it.
- **Check:** `sketchybar --query bar`, `launchctl list | grep sketchybar`. Reload: `sketchybar --reload`.
- **Remove:** drop `./sketchybar.nix` from `home-manager/home.nix` imports, `scripts/apply.sh home-manager --write`.
