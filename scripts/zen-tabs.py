#!/usr/bin/env python3
"""List Zen's open tabs as JSON lines: {"title", "url", "selected", "workspace"}. Zen (Firefox) has no AppleScript, so
the tabs come from its session file, sessionstore-backups/recovery.jsonlz4 (rewritten every few seconds while tabs
change; Mozilla's LZ4 container, decoded here without any package). Used by tools/hammerspoon/config/zen-tabs.lua.
Workspace names come from zen-sessions.jsonlz4 when it lists them."""
import configparser, json, os, struct, sys

BASE = os.path.expanduser("~/Library/Application Support/zen")


def lz4_block(src, size):
    """Decompress one LZ4 block (no frame)."""
    out, i, n = bytearray(), 0, len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        out += src[i:i + lit]; i += lit
        if i >= n: break
        off = src[i] | src[i + 1] << 8; i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(out) - off
        for k in range(ml):
            out.append(out[start + k])
    return bytes(out[:size])


def mozlz4(path):
    data = open(path, "rb").read()
    if data[:8] != b"mozLz40\0":
        raise ValueError(f"{path}: not a mozLz4 file")
    return json.loads(lz4_block(data[12:], struct.unpack("<I", data[8:12])[0]))


def profile_dir():
    ini = configparser.ConfigParser()
    ini.read(os.path.join(BASE, "profiles.ini"))
    for section in ini.sections():
        if section.startswith("Install") and ini.has_option(section, "Default"):
            return os.path.join(BASE, ini.get(section, "Default"))
    for section in ini.sections():
        if ini.get(section, "Default", fallback="0") == "1":
            return os.path.join(BASE, ini.get(section, "Path"))
    sys.exit("no Zen profile found")


def main():
    prof = profile_dir()
    session = mozlz4(os.path.join(prof, "sessionstore-backups", "recovery.jsonlz4"))
    names = {}
    try:
        zs = mozlz4(os.path.join(prof, "zen-sessions.jsonlz4"))
        for space in zs.get("spaces", []) or zs.get("workspaces", []):
            names[space.get("uuid")] = space.get("name", "")
    except Exception:
        pass
    for win in session.get("windows", []):
        selected = win.get("selected", 0)
        for idx, tab in enumerate(win.get("tabs", []), 1):
            entries = tab.get("entries") or []
            if not entries:
                continue
            e = entries[max(0, min(len(entries), tab.get("index", len(entries))) - 1)]
            url = e.get("url", "")
            if not url or url.startswith("about:"):
                continue
            ws = tab.get("zenWorkspace") or (tab.get("attributes") or {}).get("zen-workspace-id")
            print(json.dumps({"title": e.get("title") or url, "url": url, "selected": idx == selected,
                              "workspace": names.get(ws, ""), "pinned": bool(tab.get("pinned"))}, ensure_ascii=False))


if __name__ == "__main__":
    main()
