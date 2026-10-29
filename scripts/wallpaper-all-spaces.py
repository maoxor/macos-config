#!/usr/bin/env python3
"""Give every Space the wallpaper chosen last. macOS sets a wallpaper for the current Space only and keeps an
older choice per Space (native fullscreen Spaces included) in its wallpaper index; the lock screen and the
screen going to sleep then sometimes showed one of those old images. Copies the most recently set Desktop
content to every Desktop entry of ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist, then
restarts WallpaperAgent so it reloads the index. Run by theme-auto.sh after a wallpaper change; --dry-run only
lists the stale entries. Backup of the index: Index.plist.bak next to it."""
import os, plistlib, shutil, subprocess, sys

IDX = os.path.expanduser("~/Library/Application Support/com.apple.wallpaper/Store/Index.plist")


def desktops(o, path=""):
    if isinstance(o, dict):
        if isinstance(o.get("Desktop"), dict) and "Content" in o["Desktop"]:
            yield path, o["Desktop"]
        for k, v in o.items():
            yield from desktops(v, f"{path}/{k}")


def main():
    d = plistlib.load(open(IDX, "rb"))
    entries = list(desktops(d))
    if not entries:
        return
    latest = max(entries, key=lambda e: e[1].get("LastSet") or 0)[1]
    stale = [(p, e) for p, e in entries if e["Content"] != latest["Content"]]
    for p, _ in stale:
        print(f"stale wallpaper: {p}")
    if not stale or "--dry-run" in sys.argv:
        return
    for _, e in stale:
        e["Content"] = latest["Content"]
    shutil.copy2(IDX, IDX + ".bak")
    tmp = IDX + ".tmp"
    with open(tmp, "wb") as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.replace(tmp, IDX)
    subprocess.run(["killall", "WallpaperAgent"], capture_output=True)
    print(f"{len(stale)} Space(s) set to the current wallpaper")


if __name__ == "__main__":
    main()
