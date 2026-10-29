# OmniWM in this setup — complete reference

OmniWM ([upstream](https://github.com/OmniNull/OmniWM)) is the **only** window manager. It tiles windows,
owns workspaces, trackpad gestures and the Overview. Everything below describes the build and the
settings this repo installs; values marked *default* are OmniWM's own defaults.

## 1. Build: upstream + a small patch series
| Piece | Where |
|---|---|
| Pinned upstream commit | `tools/omniwm/UPSTREAM` |
| Local patches (git `format-patch` series) | `tools/omniwm/patches/0001…0029` |
| Build + sign + install | `tools/omniwm/build-local.sh` (`--check` = patches apply, no build) |
| Signing certificate (once per Mac) | `tools/omniwm/create-signing-cert.sh` |
| Working checkout | `$OMNIWM_SRC` (default `~/src/omniwm`), branch `macos-config`, recreated on every build |

Why a local build: the patches below are not upstream. Why a self-signed certificate: macOS ties the
Accessibility and Screen Recording grants to the code signature; an ad-hoc signature changes on every
build, so permissions would be lost on each rebuild. The certificate pins them (`codesign -dr -` shows
`certificate leaf = H"…"`).

| Patch | What it does | Why |
|---|---|---|
| 0001 | `OverviewHideWorkspaceLabels` default hides the workspace names/numbers on the left of the Overview | cleaner Overview (user choice) |
| 0002 | `OverviewHideSearchBar` default hides the Overview search bar (typing still filters) | idem |
| 0003 | hidden search bar keeps a 44 pt top inset | otherwise the first row sits under the notch band |
| 0004 | parking-edge masks (1 pt windows at both screen edges) show the wallpaper slice instead of black and swallow clicks; swipe captures at Retina 2x; `swipe-geometry` log | black line at the edges; clicks at the edge reached parked windows and switched workspace; soft/dull swipes (bugs B6, B7 in `docs/bugs.md`) |
| 0005 | workspace swipe leaves out Niri columns whose settled frame is clamped to the screen edge | third Niri column drawn over the second during swipes (B8) |
| 0006 | swipe previews use WindowServer-composited snapshots of the visible workspace (`NativeWindowSnapshotCache`) | per-window captures replace Ghostty's blur with an opaque material: washed-out colours during swipes (B7) |
| 0007 | `swipe-snapshot` log: which windows used a native snapshot vs the live capture | verifying 0006 |
| 0008 | a diagonal 3-finger start waits for its direction instead of cancelling the gesture | missed swipes (B9) |
| 0009 | `WorkspaceSwipeSensitivity` default (set to 1.8 in `home-manager/macos.nix`): earlier trigger, less travel per workspace | vertical swipe felt late to start |
| 0010 | wallpaper cache dropped when the desktop picture changes | stale wallpaper behind swipes/Overview |
| 0011 | `SuppressSecureInputExplanation` default: no explanation panel after 10 s of Secure Input | the panel interrupted typing in password fields (B15) |
| 0012 | no hover focus while System Settings or an auth dialog owns focus | hover stole focus from them (B14) |
| 0013 | Overview restarts the captures of an app unhidden while it is open | grey previews (B10) |
| 0014 | test: the sensitivity shortens trigger and travel | non-regression for 0009 |
| 0015 | `focus-trace` log of every focus-follows-mouse decision (hovered window, OmniWM focus, frontmost app, reason) | diagnosing focus |
| 0016 | before skipping an "already focused" window, check macOS (frontmost app + AX focused window) once per pointer entry | OmniWM's record is not updated by same-app hand-offs: the window under the pointer stayed inactive (B5) |
| 0017 | a move dropped by the 0.1 s debounce is re-evaluated once when the debounce expires | fast pointer moves left the window under the pointer unfocused: 10/15 → 0/15 measured (B5) |
| 0019 | on a workspace switch (gesture or keyboard), focus the window whose destination frame contains the pointer instead of the window remembered for that workspace | W1 o1 → W2 → pointer to o2 → back to W1 re-focused o1 although the pointer was over o2 (B5) |
| 0020 | a size read back equal to the size OmniWM last verified is stale, not a minimum | leaving fullscreen, Safari's old 2074 pt width was learned as its minimum: the column stayed full width without gaps |
| 0021 | keep the fullscreen restore offset while relayouts re-target the same column | leaving fullscreen quickly left the column at x=0 (no left gap) |
| 0022 | scroll bench: `notifyutil -p com.barut.OmniWM.bench.columnScroll` replays a fixed 3-finger gesture | reproducible measurements (`tools/omniwm/bench`) |
| 0023 | animation ticks verify the size writes they need, so later ticks move windows only | an unverified size was re-written every tick: Safari re-laid out its page each frame (−82 % size writes) |
| 0024 | the restore catalog is not saved while the startup rescan is still placing windows | quitting right after launch put every window on the active workspace at the next launch |
| 0025 | leaving a Niri column takes the same gesture whatever its width (past halfway to the next snap point, capped at a quarter of the screen) | a full-width column needed twice the gesture of a half-width one |
| 0026 | the restore catalog keeps launch entries of windows not seen again this session | a save while the screen was locked wrote an empty catalog |
| 0027 | the bench dumps the targets of its animation ticks (`~/Library/Logs/OmniWM/scroll-bench.tsv`) | input for `tools/omniwm/bench` |
| 0028 | a size write the app did not answer (AX `cannotComplete`) is not learned as the window's minimum size | after Safari left macOS fullscreen, its fullscreen size became the column minimum and Option+F did nothing until OmniWM restarted |
| 0029 | a workspace rule also places later windows of an app that is in the background or whose windows are all on that workspace, and such a window taking focus does not switch the view there | Playwright test browsers (rules → workspace 4) opened their next pages over the user's workspace and pulled the view to workspace 4 |
| 0018 | after a workspace change (once the layout refresh completes, no swipe running) and after a Niri scroll, focus the window under the still pointer | hover focus only reacted to mouse moves: arriving on a workspace left the window under the pointer unfocused (B5); 8/8 with a still pointer |

Tests added by the patches (run targeted only, never the full suite on a machine in use — it froze the
Mac once): `swift test --filter "WorkspaceSwipeNiriClampTests|ParkingEdgeMaskTests|WorkspaceSwipePreviewTests|WorkspaceSwipePreviewWarmupTests"`.

**Changing a patch:** `tools/omniwm/build-local.sh --check` → edit/commit in `$OMNIWM_SRC` on branch
`macos-config` → `git -C $OMNIWM_SRC format-patch -o <repo>/tools/omniwm/patches $(cat tools/omniwm/UPSTREAM)..HEAD`
(delete the old files first) → `build-local.sh`. **Updating upstream:** put the new commit in `UPSTREAM`,
run `--check`; if a patch no longer applies, rebase the branch and re-export.

Not ported from earlier local builds, on purpose: features rather than fixes (card Overview, drop near an
edge inserts instead of swapping, animated drops, notch full-height option — `gaps.fullHeightWhenMenuBarHidden`
is still in `settings.toml` but ignored), and a timer-based key-window re-assert (it could hand focus to the
wrong window).
Their history: `docs/bugs.md`.

## 2. Configuration files
| File | Role |
|---|---|
| `~/.config/omniwm/settings.toml` ↔ `tools/omniwm/config/settings.toml` | the full OmniWM config (captured copy) |
| `tools/omniwm/apply-registry.py` | enforces the parts this repo owns: hotkeys, gestures, workspace names, gaps, layouts, Overview look, and `singleWindowFit` computed from the main screen. Preview by default, `--write` with OmniWM **quit** (it rewrites the file otherwise). `scripts/theme-sync.sh` runs it on every wallpaper change, so the registry must always describe the wanted state (`scripts/check.sh` tests that it changes nothing in the captured file). |
| `defaults write com.barut.OmniWM …` | the two patch options (0001, 0002); set by `home-manager/macos.nix` |

## 3. Workspaces and layouts
| # | Name | Layout | Apps assigned by rule |
|---|---|---|---|
| 1 | Focus | **Dwindle** (classic tiling) | Ghostty |
| 2 | Web | **Niri** | Safari |
| 3 | Messages | Niri | Discord |
| 4 | Atelier | Niri | Finder |
| 5–9 | 5, ❤️, 🚀, 8, 9 | Niri | — |

- **Dwindle** (W1): binary splits. One window fills the work area; each new window splits the focused
  tile. Nothing scrolls; 3-finger horizontal swipes do nothing there.
- **Niri** (W2–9): windows live in **columns on an endless horizontal strip**. 2 columns are visible
  (`visibleContainerCount = 2`), each half the width (`defaultContainerPrimarySpan = 0.5`, presets ⅓ ½ ⅔).
  More windows do not shrink the others: new columns open to the right and you scroll to them. Columns
  scrolled out of view are *parked* (see §8).
- A lone window, in both layouts, gets `singleWindowFit` = screen minus the 8 pt outer gaps (computed per
  Mac by `apply-registry.py`), so no window ever touches a screen edge.
- Gaps: 8 pt between windows and at every screen edge.
- Each workspace keeps its own window order and layout state; switching never reorganises another one.
- **Empty workspaces are hidden** (`workspaceBar.hideEmptyWorkspaces = true`): swipes, next/previous and
  the Overview skip them; the active one is always shown. A workspace reappears as soon as a window lands.
- App rules also **float** System Settings, SecurityAgent and the authentication dialogs (they keep their
  own size) and list a few apps without assignment (they open on the current workspace).
- `Control+Option+G` toggles Dwindle ↔ Niri on the current workspace (runtime only; the registry restores
  the layouts above on the next apply).

## 4. Gestures (trackpad)
| Gesture | Action | Owner |
|---|---|---|
| 3 fingers **up / down** | previous / next (non-empty) workspace; the content follows the fingers vertically, release past the middle or flick to commit | OmniWM |
| 3 fingers **left / right** | scroll the Niri columns of the current workspace (snaps to columns) | OmniWM (`scrollEnabled`, `trackpadScrollStyle = snap`) |
| 4 fingers **up** | open the Overview | OmniWM |
| 2 fingers | normal scrolling (natural direction) | macOS |

How the axes never conflict: both 3-finger gestures use the same finger count, so OmniWM decides on the
**dominant axis** after a few points of travel (`TrackpadGestureIntent.swift`); when column scrolling is on,
the workspace swipe automatically takes the other axis (vertical). A diagonal start can be dropped (the
fix for that is not in this build, see §1).

macOS must not see these gestures, otherwise Mission Control / Spaces animate behind OmniWM's:
`home-manager/macos.nix` turns off the macOS 3- and 4-finger swipes (built-in and Bluetooth trackpad
domains + the per-host keys) and the Mission Control / App Exposé trackpad gestures
(`com.apple.dock showMissionControlGestureEnabled = 0`).

## 5. Overview (4 fingers up, or Hyper+O)
OmniWM's stock "Niri overview": all non-empty workspaces stacked vertically, the current one as a
horizontal strip of its windows (the "T" layout), live window previews, wallpaper behind (transparent
backdrop `overview.backdrop.alpha = 0`), `zoom = 0.5`, no labels and no search bar (patches 0001–0002).
Click a window to focus it (and its workspace); drag a window onto another workspace to move it; the empty
area at the bottom (+) creates a workspace. Previews come from ScreenCaptureKit, so OmniWM needs **Screen
Recording**; grey previews mean that permission is missing or the app is hidden (B10).

## 6. Mouse: focus, drag and drop, swap
- **Focus follows the mouse, with raise** (`focus.followsMouse = true`, `raiseOnMouseFocus = true`):
  hovering a window focuses it. Raise matters: without it OmniWM switches between two windows of one app with
  private activate/deactivate records that act on the app's current key window, which left windows drawn
  inactive while focused, or two drawn active (B5). Tiled windows never overlap, so raising is invisible.
  System Settings and auth dialogs keep focus while open (patch 0012). Diagnose with
  `/usr/bin/log stream --predicate 'subsystem == "com.barut.OmniWM" AND category == "focus-trace"'`.
- **Move / swap with the mouse**: drag a window by its title bar, or anywhere with **Option + drag**.
  Dropping on another tile **swaps** the two (upstream behaviour). The "drop on an edge inserts beside"
  and Niri stack/new-column drops of earlier local builds are not in this build (§1).
- Keyboard equivalents: §7. `Control+Option+T` floats/unfloats the focused window.

## 7. Keyboard (OmniWM)
Bindings use **QWERTY key positions** (OmniWM binds by key code): on the French AZERTY keyboard the key
printed W sends Z, A sends Q, Q sends A. The full AZERTY table, with every tool, is `docs/shortcuts.md`.
Hyper = Control+Option+Command. Option alone is never bound (it types `{ } [ ] | @` on AZERTY).

| Keys | Action |
|---|---|
| Control+1…9 / Control+Shift+1…9 | go to workspace N / send the window there |
| Control+Option+Tab | previous workspace (back and forth) |
| Control+←/→/↑/↓ | focus the neighbouring window |
| Control+Shift+←/→/↑/↓ | move the window: Dwindle swaps with the neighbour; Niri ←/→ moves it into the next column (stacks there), ↑/↓ reorders it inside its column |
| Control+Option+Shift+←/→ | move the column (Niri) |
| Control+Option+Shift+↑/↓ (PgUp/PgDn = column) | send window / column to the workspace above/below |
| Control+Option+1…9, Home/End | focus column N, move column to first/last |
| Control+Option+F | fullscreen |
| Control+Option+R / E / S | balance sizes / toggle split orientation / swap split (Dwindle) |
| Control+Option+(W key) / (Q key) | grow / shrink the focused window |
| Control+Option+(A key) / D / (Z key) / C | preselect left / right / down / clear (Dwindle) |
| Control+Option+G | toggle Dwindle ↔ Niri on this workspace |
| Control+Option+T / X / M | float toggle / rescue off-screen windows / menu anywhere |
| Hyper+O / Hyper+Space / Hyper+Return | Overview / command palette / quake terminal |

## 8. How OmniWM moves windows (and what that implies)
- macOS has no public API to move another app's windows except **Accessibility (AX)**: OmniWM asks each
  app's process to move/resize its window. That is why animations of real windows are limited by the
  apps (heavy apps update slowly) and why OmniWM needs Accessibility.
- **Workspaces are not macOS Spaces.** Windows of inactive workspaces (and Niri columns scrolled away)
  are *parked*: moved so that only 1 pt stays on screen at the right edge (macOS refuses fully off-screen
  windows). OmniWM's 1 pt `ParkingEdgeMask` hides that point (patch 0004); their shadow would still darken
  the 8 pt right gap, so Hammerspoon's `margin-veil.lua` covers the gap with the matching wallpaper slice
  and swallows clicks there (`docs/bugs.md` B6).
- **Swipes and the Overview animate captures, not windows**: at the first trackpad contact OmniWM
  prepares images of the source and destination workspaces and animates those layers in its own panel
  (smooth regardless of how slowly apps answer AX); the real windows are placed once, at the end. Patch 0006 makes
  the visible workspace's images WindowServer-composited (identical to the screen, keeps Ghostty's blur);
  a destination workspace uses its last native snapshot (taken when you last left it) or a live capture.
- Focus is given with private SkyLight calls (same technique as yabai): front process + key-window
  event records (`PrivateAPIs.swift`).

## 9. Interaction with other components
| Component | Interaction |
|---|---|
| Hammerspoon `ws-hide.lua` | subscribes to OmniWM IPC (`omniwmctl subscribe`); after a workspace switch it focuses the window under the pointer (or the first one) when OmniWM could not; feeds `margin-veil`. It no longer hides apps despite its name. |
| Hammerspoon `margin-veil.lua` | wallpaper strip over the right gap (above parked windows, below OmniWM's panels) |
| Hammerspoon `ax-guard.lua` | restarts OmniWM and Neru when an Accessibility grant changes (revoking it used to freeze input) |
| Ghostty | tiled on Focus; its blur/transparency is why patch 0006 exists |
| Safari / Discord / Finder | assigned by rule to Web / Messages / Atelier, tiled |
| Neru | keyboard hints/scrolling; independent; also needs Accessibility |
| macOS | Stage Manager off (`com.apple.WindowManager GloballyEnabled = 0`): with it on, workspace switches showed empty screens |
| theme | `scripts/theme-sync.sh` recolours OmniWM's border settings and re-applies the registry on wallpaper change |

## 10. Diagnostics
- `scripts/doctor.sh` — OmniWM signed with the stable certificate, running, IPC answering, Niri present,
  registry = settings, macOS gesture settings.
- `omniwmctl query workspaces|windows`, `omniwmctl command switch-workspace N`.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.barut.OmniWM"'` (categories `swipe-geometry`,
  `swipe-snapshot`). Under zsh, plain `log` is a shell builtin: always use `/usr/bin/log`.
- Emergency: `scripts/emergency-stop.sh` / `emergency-start.sh`, `docs/recovery.md`.
