#!/usr/bin/env python3
"""Playwright test browsers (Claude Code experiments) open their pages behind the user's windows on macOS.

Headed Chromium shows each new page window for 20-35 ms at the front, over whatever the user is doing, before
OmniWM parks it on workspace 4: a flash every few seconds while a session runs browser tests. Playwright creates
every page with the CDP command Target.createTarget; with background: true (as in Playwright PR #41282) Chrome
opens the window behind the others. Measured on 2026-10-29 (120 fps screen video): 0 flashes in 15 runs against
a flash in every run before; GPU (ANGLE Metal), pixels, frame rate (123 fps), wheel, keyboard, clicks, hover,
drag and drop, screenshots and video recording are identical with and without it.

Patches every playwright-core under ~/dev and ~/.npm/_npx (projects reinstall it, so this runs hourly from the
launchd agent playwright-background-pages). PW_FOREGROUND_PAGES=1 in a process restores the normal behaviour.
--undo restores the original lines; --check only lists the files."""
import os, sys

ROOTS = [os.path.expanduser(p) for p in ("~/dev", "~/.npm/_npx")]
OLD = 'send("Target.createTarget", { url: "about:blank", browserContextId: this._browserContextId });'
NEW = ('send("Target.createTarget", { url: "about:blank", browserContextId: this._browserContextId, '
       '...(process.platform === "darwin" && this._browser.options.headful && !process.env.PW_FOREGROUND_PAGES '
       '? { background: true } : {}) /* macos-config: pages open behind the user\'s windows */ });')


def files():
    for root in ROOTS:
        for d, dirs, names in os.walk(root):
            dirs[:] = [x for x in dirs if x not in (".git", ".Trash", "@cloudflare") and not x.startswith(".venv")]
            if os.path.basename(d) in ("lib", "chromium") and "playwright-core" in d:
                for n in ("coreBundle.js", "crBrowser.js"):
                    if n in names:
                        yield os.path.join(d, n)


def main():
    undo, check = "--undo" in sys.argv, "--check" in sys.argv
    for f in files():
        s = open(f, encoding="utf-8").read()
        src, dst = (NEW, OLD) if undo else (OLD, NEW)
        if s.count(src) != 1:
            if check:
                print(("patched  " if NEW in s else "unknown  ") + f)
            continue
        if check:
            print("pending  " + f)
            continue
        open(f, "w", encoding="utf-8").write(s.replace(src, dst))
        print(("restored " if undo else "patched  ") + f)


if __name__ == "__main__":
    main()
