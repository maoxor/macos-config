# Raycast

Launcher and the single clipboard history. Free version, no account needed.

- **Install:** Homebrew cask. **Start:** Raycast's own "Open at Login" (the only startup mechanism).
- **Permission:** Accessibility.
- **Depends on:** Spotlight removed from Cmd+Space (symbolichotkeys 64 disabled in `home-manager/macos.nix`).
- **Config:** stored in Raycast's encrypted databases; nothing is captured from them. What the repo owns is
  file-based: the script commands below and the backdrop (`tools/hammerspoon/config/raycast-dim.lua`).

## Logic: one hotkey, then one letter
Cmd+Space opens Raycast; a one-letter **alias** then picks the command. Aliases need no new key combination, so they
never conflict with an app, AZERTY or OmniWM, and they stay with the left hand.

| Alias | Command | Comes from |
|---|---|---|
| `v` | Clipboard History | Raycast |
| `f` | Chercher une fenêtre (every window of every workspace) | script command, opens OmniWM's palette |
| `m` | Search Menu Items (any menu entry of the front app) | Raycast |
| `s` | Search Snippets | Raycast |
| `t` | Search Browser Tabs | Raycast (needs its Safari extension: command "Install Browser Extension") |
| `e` | Search Emoji & Symbols | Raycast |

## Backdrop
While the launcher panel is on screen, everything behind it is dimmed (45 % black, 0.12 s fade). Raycast has no such
setting; Hammerspoon draws it (`raycast-dim.lua`): an Accessibility observer and a passive watch of Cmd+Space show
it, a 100 ms check of the window list removes it. It ignores the mouse, and Settings / AI Chat windows dim nothing.
Check: `hs -c 'return raycastDim.status()'` (counts the shows per trigger). Off: `hs -c 'raycastDim.stop()'`.

## Script commands (`script-commands/`)
Plain shell files tracked here, so they come back on a new Mac. They expose this setup's own actions by name:

| Title | Does | Also |
|---|---|---|
| Chercher une fenêtre | OmniWM's window palette | Hyper+Space |
| État du Mac | memory / CPU / GPU over 24 h, heaviest processes, memory-guard margin | `perf-journal.py report` |
| Fond d'écran suivant | next wallpaper, the theme follows | F3 |
| Nettoyer le clavier | keyboard locked until a click on the card | F4 |
| Restaurer les sessions | reopen apps and Claude Code sessions after a crash (asks first) | Cmd+F5 twice |

## Manual setup (once; Raycast keeps it in its own database)
1. Raycast hotkey: Cmd+Space.
2. Settings > Extensions > Script Commands > **Add Directories** → this repo's `tools/raycast/script-commands`.
3. Aliases of the table above: Settings > Extensions, select the command, field "Alias".
4. Clipboard History: keep 1 week; exclude Keychain Access and your password manager.
5. Optional backup: Settings > Advanced > Export (password-protected `.rayconfig`), stored **outside** the repo.

Restore: Settings > Advanced > Import, or redo the steps above.

## Not used, on purpose
- Raycast Window Management: OmniWM owns windows.
- A second clipboard manager, a second launcher.
- Raycast Pro (paid): AI and cloud sync are not needed here.
