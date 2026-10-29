#!/usr/bin/env python3
"""Playwright test browsers (Claude Code experiments) open their pages behind the user's windows, in the bottom-right
corner of the screen, on macOS.

Headed Chromium shows each new page window for 20-35 ms at the front, over whatever the user is doing, before
OmniWM parks it on workspace 4: a flash every few seconds while a session runs browser tests. Playwright creates
every page with the CDP command Target.createTarget; with background: true (as in Playwright PR #41282) Chrome
opens the window behind the others. Measured on 2026-10-29 (120 fps screen video): 0 flashes in 15 runs against
a flash in every run before; GPU (ANGLE Metal), pixels, frame rate (123 fps), wheel, keyboard, clicks, hover,
drag and drop, screenshots and video recording are identical with and without it.
Behind is not hidden: Ghostty is translucent (background-opacity 0.88), so a 1200x1257 window born at 22,61 still
showed through the terminals for 20-85 ms (more under load, and the dark test pages painted 20 ms after OmniWM
parked it). left/top put a new context's window in the bottom-right corner instead: Chrome keeps 40 x 41 pt of it on
screen (it clamps any position), where OmniWM parks it in ~20 ms (measured 2026-10-29).

Patches every playwright-core (npm) and Python Playwright driver under ROOTS, the session scratchpads included
(projects and sessions reinstall it, so this runs every 5 minutes from the launchd agent
playwright-background-pages). PW_FOREGROUND_PAGES=1 in a process restores the normal behaviour.
--undo restores the original lines; --check only lists the files."""
import glob, os, sys

ROOTS = [os.path.expanduser(p) for p in ("~/dev", "~/src", "~/ai", "~/.npm/_npx", "~/.cache/codex-runtimes")]
ROOTS.append(f"/private/tmp/claude-{os.getuid()}")  # Claude Code session scratchpads
SKIP = {".git", ".Trash", "__pycache__", "Library"}
OLD = 'send("Target.createTarget", { url: "about:blank", browserContextId: this._browserContextId });'
NEW_V1 = ('send("Target.createTarget", { url: "about:blank", browserContextId: this._browserContextId, '
          '...(process.platform === "darwin" && this._browser.options.headful && !process.env.PW_FOREGROUND_PAGES '
          '? { background: true } : {}) /* macos-config: pages open behind the user\'s windows */ });')
NEW = ('send("Target.createTarget", { url: "about:blank", browserContextId: this._browserContextId, '
       '...(process.platform === "darwin" && this._browser.options.headful && !process.env.PW_FOREGROUND_PAGES '
       '? { background: true, ...(this._browserContextId ? { left: 100000, top: 100000 } : {}) } : {}) '
       '/* macos-config: pages open behind the user\'s windows, in the bottom-right corner */ });')
# Where a package sits inside node_modules (npm, nested, pnpm) and inside site-packages: these trees are not walked.
IN_NODE_MODULES = ("playwright-core", "*/node_modules/playwright-core", "@*/*/node_modules/playwright-core",
                   ".pnpm/playwright-core@*/node_modules/playwright-core")
IN_SITE_PACKAGES = ("playwright/driver/package",)


def packages():
    for root in ROOTS:
        for d, dirs, _ in os.walk(root):
            name = os.path.basename(d)
            patterns = IN_NODE_MODULES if name == "node_modules" else IN_SITE_PACKAGES if name == "site-packages" else ()
            if patterns:
                dirs[:] = []
                for p in patterns:
                    yield from glob.glob(os.path.join(d, p))
            else:
                dirs[:] = [x for x in dirs if x not in SKIP]


def files():
    for p in packages():
        for n in ("lib/coreBundle.js", "lib/server/chromium/crBrowser.js"):
            if os.path.isfile(os.path.join(p, n)):
                yield os.path.join(p, n)


def main():
    undo, check = "--undo" in sys.argv, "--check" in sys.argv
    for f in files():
        s = open(f, encoding="utf-8").read()
        src = next((x for x in ((NEW, NEW_V1) if undo else (OLD, NEW_V1)) if s.count(x) == 1), None)
        if src is None:
            if check:
                print(("patched  " if NEW in s else "unknown  ") + f)
            continue
        if check:
            print("pending  " + f)
            continue
        open(f, "w", encoding="utf-8").write(s.replace(src, OLD if undo else NEW))
        print(("restored " if undo else "patched  ") + f)


if __name__ == "__main__":
    main()
