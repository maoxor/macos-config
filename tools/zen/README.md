# Zen Browser

Main browser since 2026-11-03 (Safari stays installed; Helium is the development browser). Firefox engine, vertical
tabs, workspaces, split view, Glance (Option+click opens a link in a floating preview).

- **Install:** Homebrew cask `zen`; then `tools/zen/apply-profile.sh` (Zen closed). It copies `user.js` into the default
  profile and places two add-ons signed by addons.mozilla.org: **uBlock Origin** (ads, trackers) and **Auto Tab
  Discard** (MPL-2.0): a tab unused for 10 min is unloaded once more than 6 tabs are open, pinned, audible and
  unsaved-form tabs excepted; a click reloads it. After a restart, restored tabs stay unloaded until clicked, and an
  unloaded tab is drawn faded. Zen dropped its own timed unloader in 1.12.9b (`zen.tab-unloader.timeout-minutes` is a
  leftover nothing reads), and on macOS Firefox's low-memory unloader never runs (`browser.lowMemoryResponseMask` = 0,
  kept so by the maintainers: the macOS memory watcher is unreliable; zen-browser/desktop#15619): the add-on is what
  unloads tabs.
- **Workspace:** OmniWM rule → workspace 2 Web, tiled (`tools/omniwm/config/settings.toml`).
- **Default browser:** System Settings > Desktop & Dock > Default web browser (macOS asks the user to confirm).
- **Config owned here:** `user.js` (Ctrl+Tab in recently used order, session restored at start, no telemetry,
  add-ons enabled without a prompt). Zen rereads it at each start: a value changed in Settings comes back, so change it
  here and rerun `apply-profile.sh`. Not in `tools/configs.tsv`: the profile folder has a random name.
- **Everything else** (workspaces, pinned tabs, theme, imported Safari data) is personal, in the profile.

## Shortcuts (same logic as the rest of the setup)
| Keys | Effect | Owner |
|---|---|---|
| Cmd+← / Cmd+→ (outside a text field) | previous / next tab | Hammerspoon `safari-tabs.lua` (same keys in Safari and Helium) |
| Ctrl+Tab | last used tab | Zen (`browser.ctrlTab.sortByRecentlyUsed`) |
| Cmd+1…9 | tab 1–9 | Zen |
| Cmd+T, then type | search the open tabs too (Zen's address bar lists them) | Zen |
| Cmd+Space, `t` | search every tab from anywhere | Raycast extension "Zen Browser" (Keyruu), store, free |

Zen's own shortcuts (compact mode, workspaces, split view) are listed and rebound in Settings > Keyboard Shortcuts;
keep them off Ctrl+digit, Ctrl+arrow, Ctrl+Shift+arrow, Ctrl+Option+letter (OmniWM) and Option+letter (AZERTY).

## Check
`python3 -c 'import json,sys; [print(a["id"], a["active"]) for a in json.load(open(sys.argv[1]))["addons"] if a["location"]=="app-profile"]' "<profile>/extensions.json"`
prints both add-ons `True`.

## Rollback
Remove the profile's `user.js`, uninstall the add-ons in Zen, `brew uninstall --cask zen`; restore Safari as the
default browser; `git revert` the commit (OmniWM rule, Hammerspoon tab keys).
