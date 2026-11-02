#!/usr/bin/env python3
"""Every minute (launchd): record the open Claude Code sessions (claude and claude2) and the OmniWM workspace of
their Ghostty window, so restore-session.py can reopen them after a crash.
~/.local/state/session-snapshot/current.json holds this boot; on the first run of a new boot it becomes
previous-boot.json (what a crash left), which restore-session.py prefers. A session that ended loses its stale
Artifact comment monitors (claude_monitors.py); each boot adds a line to boot-history.log."""
import base64, json, os, subprocess, sys, time

import claude_monitors

STATE = os.path.expanduser("~/.local/state/session-snapshot")
BOOT_LOG = os.path.expanduser("~/Library/Logs/macos-config/boot-history.log")
CTL = os.path.expanduser("~/.local/bin/omniwmctl")
CONFIGS = {os.path.expanduser("~/.claude"): None, os.path.expanduser("~/.claude-2"): os.path.expanduser("~/.claude-2")}


def boot_time():
    return subprocess.run(["sysctl", "-n", "kern.boottime"], capture_output=True, text=True).stdout.split(",")[0]


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def parents(pid):
    out = []
    while pid > 1:
        out.append(pid)
        r = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        pid = int(r) if r else 0
    return out


def window_workspaces():
    """Ghostty process pid -> workspace number (window ids encode 'uuid:pid:wid')."""
    try:
        data = json.loads(subprocess.run([CTL, "query", "windows", "--format", "json"], capture_output=True,
                                         text=True, timeout=5).stdout)
    except Exception:
        return {}
    out = {}
    for w in data["result"]["payload"]["windows"]:
        if w["app"]["name"] != "Ghostty":
            continue
        try:
            pid = int(base64.b64decode(w["id"][3:] + "==").decode().split(":")[1])
        except Exception:
            continue
        out.setdefault(pid, w["workspace"]["number"])
    return out


def sessions():
    spaces = window_workspaces()
    out = []
    for root, config in CONFIGS.items():
        d = os.path.join(root, "sessions")
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if not name.endswith(".json"):
                continue
            try:
                s = json.load(open(os.path.join(d, name)))
            except Exception:
                continue
            pid = s.get("pid")
            if s.get("kind") != "interactive" or not s.get("sessionId") or not pid or not alive(pid):
                continue
            ws = next((spaces[p] for p in parents(pid) if p in spaces), None)
            out.append({"config": config, "sessionId": s["sessionId"], "cwd": s.get("cwd"), "name": s.get("name"),
                        "workspace": ws, "startedAt": s.get("startedAt", 0)})
    return sorted(out, key=lambda s: s["startedAt"])


def log_boot():
    """What ended the last boot and started this one: their meaning shows by comparing boots, and the unified log
    keeps them for days only."""
    def sysctl(name):
        return subprocess.run(["sysctl", "-n", name], capture_output=True, text=True).stdout.strip()
    with open(BOOT_LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')} boot={sysctl('kern.bootreason')} "
                f"shutdown={sysctl('kern.shutdownreason')}\n")


def main():
    os.makedirs(STATE, exist_ok=True)
    cur = os.path.join(STATE, "current.json")
    boot = boot_time()
    try:
        old = json.load(open(cur))
    except Exception:
        old = None
    if old and old.get("boot") != boot:
        os.replace(cur, os.path.join(STATE, "previous-boot.json"))
        log_boot()
    if old:
        claude_monitors.clear_ended(old.get("sessions", []), rebooted=old.get("boot") != boot)
    snap = {"boot": boot, "sessions": sessions()}
    # At shutdown the sessions end before this job does: an empty run keeps the last list of the same boot.
    if not snap["sessions"] and old and old.get("boot") == boot:
        return
    tmp = cur + ".tmp"
    json.dump(snap, open(tmp, "w"), indent=1)
    os.replace(tmp, cur)


if __name__ == "__main__":
    sys.exit(main())
