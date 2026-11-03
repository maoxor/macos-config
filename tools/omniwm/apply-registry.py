#!/usr/bin/env python3
"""Apply the settings this repo owns (hotkeys, gestures, layouts, gaps, Overview) to OmniWM's settings.toml.

Usage: python3 -I apply-registry.py <settings.toml> [--write]
Without --write: print the planned changes, write nothing.
Quit OmniWM before --write (it rewrites the file otherwise).

Rules:
- Hyper = Control+Option+Command; adding Shift = send/move.
- Any "Option+..." binding without Control or Command is unassigned: on a French AZERTY keyboard those
  chords type { } [ ] | @ ~ etc.
- IPC enabled (required by Hammerspoon and omniwmctl).
- Workspaces 1-4 are labelled Focus / Web / Messages / Atelier through displayName (name stays numeric).
"""
import os
import re
import sys

H = "Hyper+"  # form OmniWM writes when hyperKeyModifiers = Control+Option+Command
# OmniWM binds keys by POSITION (ANSI/QWERTY key codes), not by character:
# the key printed W on AZERTY is position Z on QWERTY. E, D, T, O, F are at the same position.
AZ_W = "Z"
HS = "Hyper+Shift+"
REGISTRY = {
    # Workspaces: two left-hand keys (Hyper was judged too awkward). Control+digit is free in macOS
    # (its "switch to desktop N" shortcuts are disabled in home-manager/macos.nix) and in terminals.
    "switchWorkspace.0": "Control+1", "switchWorkspace.1": "Control+2",
    "switchWorkspace.2": "Control+3", "switchWorkspace.3": "Control+4",
    "moveToWorkspace.0": "Control+Shift+1", "moveToWorkspace.1": "Control+Shift+2",
    "moveToWorkspace.2": "Control+Shift+3", "moveToWorkspace.3": "Control+Shift+4",
    # Previous window: Option+Tab types no character (the one exception to "never Option alone").
    "focusPrevious": "Option+Tab",
    # Four directions, one scheme: Control+arrow = focus, Control+Shift+arrow = move (swap with the
    # neighbour; in a Niri column up/down reorders the stack). macOS held these chords (symbolic hotkeys
    # 79-82 spaces, 32-35 Mission Control / application windows): disabled in home-manager/macos.nix.
    "focus.left": "Control+Left Arrow", "focus.right": "Control+Right Arrow",
    "focus.up": "Control+Up Arrow", "focus.down": "Control+Down Arrow",
    "move.left": "Control+Shift+Left Arrow", "move.right": "Control+Shift+Right Arrow",
    "move.up": "Control+Shift+Up Arrow", "move.down": "Control+Shift+Down Arrow",
    "toggleOverview": H + "O",
    "openCommandPalette": H + "Space",
    "toggleQuakeTerminal": H + "Return",
    # Dwindle controls: Control+Option + a left-hand letter. Names are QWERTY POSITIONS:
    # printed AZERTY W = "Z", Q = "A", A = "Q", Z = "W" (E R S D F G T X C are the same).
    "toggleFullscreen": "Control+Option+F",            # temporary fullscreen
    # Niri full width toggle (columns keep the 8 pt gaps). Exception to "never Option alone", asked for:
    # on AZERTY it costs the "ƒ" character.
    "toggleContainerFullPrimarySpan": "Option+F",
    "expandContainerToAvailablePrimarySpan": "Unassigned", "resetWindowSecondarySpan": "Unassigned",
    "balanceSizes": "Control+Option+R",                # equal shares
    "toggleSplit": "Control+Option+E",                 # side by side <-> stacked
    "swapSplit": "Control+Option+S",                   # swap the two halves
    "resizeFocusedWindow.grow": "Control+Option+Z", "resizeFocusedWindow.shrink": "Control+Option+A",
    "toggleFocusedWindowFloating": "Control+Option+T", # floating <-> tiled
    "toggleWorkspaceLayout": "Control+Option+G",       # Dwindle <-> Niri on this workspace
    "rescueOffscreenWindows": "Control+Option+X",      # bring off-screen windows back
    "preselect.left": "Control+Option+Q", "preselect.right": "Control+Option+D",
    "preselect.down": "Control+Option+W", "preselectClear": "Control+Option+C",
}
NAMES = {"1": "Focus", "2": "Web", "3": "Messages", "4": "Atelier"}
INVERSE = {v: k for k, v in NAMES.items()}
GENERAL = {"ipcEnabled": "true", "animationSpeed": "1.0",  # OmniWM default speed
           "updateChecksEnabled": "false",  # patched local build: never auto-update to upstream
           "hyperKeyModifiers": '"Control+Option+Command"'}
# OmniWM's window border and workspace bar stay off: the focused-window border is JankyBorders (home-manager/borders.nix;
# OmniWM's, tried 2026-11-03, was judged poor). Their settings are kept; the colour follows the palette accent.
SECTIONS = {
    "[borders]": {"enabled": "false", "width": "2.0"},
    "[borders.color]": {"red": "0.5686", "green": "0.7294", "blue": "1.0", "alpha": "0.85"},
    # Gestures: 3 fingers vertical = workspaces,
    # 3 fingers horizontal = Niri columns, 4 fingers up = OmniWM Overview (macOS Mission Control
    # gesture turned off: com.apple.dock showMissionControlGestureEnabled = 0).
    "[gestures]": {"fingerCount": "3", "scrollEnabled": "true", "workspaceSwipeEnabled": "true",
                   "workspaceSwipeAxis": '"vertical"', "workspaceSwipeFingerCount": "3",
                   "overviewGestureEnabled": "true", "overviewGestureFingerCount": "4"},
    # Default layout for workspaces without their own layoutType (workspace 1; 2-9 are Niri in settings.toml).
    "[general]": {"defaultLayoutType": '"dwindle"'},
    # A lone window gets the screen minus the outer gaps ("fill" would touch the edges): see screen_fit().
    "[dwindle]": {"singleWindowFit": None},
    # Niri: 2 visible columns, each half the width.
    "[niri]": {"visibleContainerCount": "2", "defaultContainerPrimarySpan": "0.5", "edgeGaps": "false",
               "singleWindowFit": None},
    # Overview: zoom 0.5, transparent backdrop (wallpaper visible behind).
    "[overview]": {"zoom": "0.5"},
    "[overview.backdrop]": {"alpha": "0.0"},
    # Focus follows the mouse WITH raise: without it OmniWM switches between two windows of one app with
    # private activate/deactivate records that act on the app's current key window (not the addressed one),
    # leaving windows drawn inactive while focused, or two drawn active (docs/bugs.md B5).
    # Tiled windows never overlap, so raising is invisible; OmniWM still avoids covering floating windows.
    "[focus]": {"followsMouse": "true", "raiseOnMouseFocus": "true"},
    "[gaps]": {"size": "8.0", "fullHeightWhenMenuBarHidden": "true"},
    # fullHeightWhenMenuBarHidden belonged to an earlier local build; the current one ignores it.
    "[gaps.outer]": {"top": "8.0",
                     "bottom": "8.0", "left": "8.0", "right": "8.0"},
    "[workspaceBar]": {"enabled": "false", "transparentBackground": "true", "showLabels": "true",
                       "hideEmptyWorkspaces": "true", "deduplicateAppIcons": "true",
                       "reserveLayoutSpace": "false"},  # bar disabled; set "true" if you enable it
}


def conflicts_with_typing(binding):
    parts = binding.split("+")
    if binding == "Option+Tab":
        return False
    return "Option" in parts and "Control" not in parts and "Command" not in parts and "Hyper" not in parts


def palette_border():
    """Border colour = base0D (accent) of the palette in home-manager/palette.nix (the source of truth,
    generated from the wallpaper), so the result is the same on every machine and in CI."""
    nix = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "home-manager", "palette.nix")
    m = re.search(r'base0D\s*=\s*"#?([0-9a-fA-F]{6})"', open(nix).read()) if os.path.exists(nix) else None
    if not m:
        return
    h = m.group(1)
    r, g, b = (round(int(h[i:i + 2], 16) / 255, 4) for i in (0, 2, 4))
    SECTIONS["[borders.color]"] = {"red": str(r), "green": str(g), "blue": str(b), "alpha": "0.85"}


def screen_fit(gap=8):
    """A lone window = the main screen minus the 8 pt outer gaps on each side, e.g. "2058x1324" on a
    2074x1340 display ("fill" would ignore the gaps and touch the edges). Computed on the Mac that
    runs this script, so it follows another screen size or resolution; "fill" if it cannot be read."""
    import subprocess
    if os.environ.get("OMNIWM_SCREEN"):  # tests / CI without a screen: "WIDTHxHEIGHT"
        w, h = (int(v) for v in os.environ["OMNIWM_SCREEN"].split("x"))
        return '"%dx%d"' % (w - 2 * gap, h - 2 * gap)
    try:
        out = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e",
                              'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame;'
                              ' Math.round(f.size.width)+"x"+Math.round(f.size.height)'],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        w, h = (int(v) for v in out.split("x"))
        return '"%dx%d"' % (w - 2 * gap, h - 2 * gap)
    except Exception:
        return '"fill"'


for _section in ("[dwindle]", "[niri]"):
    SECTIONS[_section]["singleWindowFit"] = screen_fit()


def main():
    palette_border()
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path, write = sys.argv[1], "--write" in sys.argv[2:]
    lines = open(path, encoding="utf-8").read().split("\n")
    changes, inserts, section = [], [], None
    # [[hotkeys]] blocks: "binding" line followed by its "id" line (order written by OmniWM)
    for i, line in enumerate(lines):
        if line.startswith("["):
            section = line.strip()
        if section in SECTIONS:
            m = re.match(r'^(\w+) = (.*)$', line)
            want = SECTIONS[section].get(m.group(1)) if m else None
            if want is not None and m.group(2) != want:
                changes.append((i, f"{m.group(1)} = {want}"))
        if section == "[general]":
            m = re.match(r'^(\w+) = (.*)$', line)
            if m and m.group(1) in GENERAL and m.group(2) != GENERAL[m.group(1)]:
                changes.append((i, f"{m.group(1)} = {GENERAL[m.group(1)]}"))
        if section == "[[workspaces]]":
            # OmniWM ignores a workspace whose "name" is not numeric: the name stays the digit and the
            # label goes into displayName.
            m = re.match(r'^name = "(.*)"$', line)
            if m:
                num = INVERSE.get(m.group(1), m.group(1))
                if num != m.group(1):
                    changes.append((i, f'name = "{num}"'))
                if num in NAMES:
                    label = f'displayName = "{NAMES[num]}"'
                    # displayName comes before id in the block (order written by OmniWM)
                    j = i
                    while j > 0 and not lines[j].startswith("[[workspaces]]"):
                        j -= 1
                    block = lines[j + 1:i]
                    cur = [k for k, l in enumerate(block, j + 1) if l.startswith("displayName = ")]
                    if cur and lines[cur[0]] != label:
                        changes.append((cur[0], label))
                    elif not cur:
                        inserts.append((j + 1, label))
        if section == "[[hotkeys]]" and line.startswith("binding = "):
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            m = re.match(r'^id = "(.*)"$', nxt)
            if not m:
                continue
            hid, cur = m.group(1), line[len('binding = "'):-1]
            want = REGISTRY.get(hid)
            if want is None and conflicts_with_typing(cur):
                want = "Unassigned"
            if want and want != cur:
                changes.append((i, f'binding = "{want}"'))
    # A registry binding must not already be used by another action
    used = {}
    for i, line in enumerate(lines):
        if line.startswith("binding = ") and i + 1 < len(lines):
            new = dict(changes).get(i, line)
            b = new[len('binding = "'):-1]
            if b != "Unassigned":
                used.setdefault(b, []).append(lines[i + 1])
    dup = {b: ids for b, ids in used.items() if len(ids) > 1}
    for i, new in changes:
        ctx = lines[i + 1].strip() if lines[i].startswith("binding") else ""
        print(f"{i + 1:5d}: {lines[i].strip()}  ->  {new}  {ctx}")
    for i, new in inserts:
        print(f"{i + 1:5d}: (insert)  ->  {new}")
    print(f"{len(changes) + len(inserts)} change(s)")
    if dup:
        print("DUPLICATE BINDINGS:", dup)
        sys.exit(1)
    if write and (changes or inserts):
        for i, new in changes:
            lines[i] = new
        for i, new in sorted(inserts, reverse=True):
            lines.insert(i, new)
        # Atomic replace: OmniWM hot-reloads settings.toml and must never read a half-written file.
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        os.replace(tmp, path)
        print("written:", path)


if __name__ == "__main__":
    main()
