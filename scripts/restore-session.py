#!/usr/bin/env python3
"""Cmd+F5 (Hammerspoon): reopen what a crash closed. Launches Ghostty, Safari and Discord (they restore their own
windows), reopens every Claude Code session of the last snapshot that is not running (claude or claude2, in its
folder, in a new Ghostty window, moved back to its workspace), then puts app windows back on their workspaces.
Uses previous-boot.json (written by session-snapshot.py) when it exists and has not been restored yet, else
current.json (sessions closed by mistake during this boot). Safe to run twice: running sessions are skipped."""
import json, os, shlex, subprocess, time

HOME = os.path.expanduser("~")
STATE = f"{HOME}/.local/state/session-snapshot"
CTL = f"{HOME}/.local/bin/omniwmctl"
REPO = f"{HOME}/dev/macos-config"
# Variables a Claude Code process passes to its children; inherited, they turn transcript saving off.
CLEAN = ["CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID",
         "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CODE_EXECPATH",
         "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_PID", "CLAUDE_EFFORT", "CLAUDE_CONFIG_DIR"]


def log(msg):
    print(time.strftime("%F %T"), msg, flush=True)


def running_ids():
    ids = set()
    for root in (f"{HOME}/.claude", f"{HOME}/.claude-2"):
        d = f"{root}/sessions"
        for name in os.listdir(d) if os.path.isdir(d) else []:
            try:
                s = json.load(open(f"{d}/{name}"))
                os.kill(s["pid"], 0)
                ids.add(s["sessionId"])
            except Exception:
                pass
    return ids


def applescript_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def ghostty_windows():
    try:
        data = json.loads(subprocess.run([CTL, "query", "windows", "--format", "json"], capture_output=True,
                                         text=True, timeout=5).stdout)
    except Exception:
        return []
    return [w for w in data["result"]["payload"]["windows"] if w["app"]["name"] == "Ghostty"]


def main():
    env = {k: v for k, v in os.environ.items() if k not in CLEAN}
    prev, cur = f"{STATE}/previous-boot.json", f"{STATE}/current.json"
    path = prev if os.path.exists(prev) else cur
    try:
        snap = json.load(open(path))
    except Exception:
        snap = {"sessions": []}
    log(f"snapshot {os.path.basename(path)}: {len(snap['sessions'])} sessions")

    for app in ("Ghostty", "Safari", "Discord"):
        subprocess.run(["/usr/bin/open", "-g", "-a", app], env=env)
    time.sleep(3)

    live = running_ids()
    for s in snap["sessions"]:
        if s["sessionId"] in live:
            continue
        # A new window of the running Ghostty, opened by AppleScript with the command typed into its shell:
        # `open -na Ghostty --args -e ...` made Ghostty 1.3 ask "Allow Ghostty to execute" for every session,
        # and a second Ghostty instance opens no window at all after a reboot. Ghostty may carry a Claude
        # child marker in its environment, so the typed command clears it first.
        cmd = f"unset {' '.join(CLEAN)}; "
        # Set for this command only: exported, it stayed in the shell and a later plain `claude` there ran account 2.
        if s.get("config"):
            cmd += f"CLAUDE_CONFIG_DIR={shlex.quote(s['config'])} "
        cmd += f"claude --resume {s['sessionId']}"
        before = {x["id"] for x in ghostty_windows()}
        script = ('tell application "Ghostty"\n set cfg to new surface configuration\n'
                  f' set initial working directory of cfg to {applescript_string(s.get("cwd") or HOME)}\n'
                  f' set initial input of cfg to {applescript_string(cmd)} & linefeed\n'
                  ' new window with configuration cfg\nend tell')
        r = subprocess.run(["/usr/bin/osascript", "-e", script], env=env, capture_output=True, text=True)
        if r.returncode != 0:
            log(f"could not open a window for {s.get('name') or s['sessionId']}: {r.stderr.strip()}")
            continue
        log(f"reopened {s.get('name') or s['sessionId']} in {s.get('cwd')}")
        w = None
        for _ in range(20):
            time.sleep(0.5)
            w = next((x for x in ghostty_windows() if x["id"] not in before), None)
            if w:
                break
        if w and s.get("workspace") and w["workspace"]["number"] != s["workspace"]:
            subprocess.run([CTL, "window", "move-to-workspace", w["id"], str(s["workspace"])],
                           capture_output=True)

    if path == prev:
        os.replace(prev, f"{STATE}/restored-{time.strftime('%Y%m%d-%H%M%S')}.json")
    subprocess.run(["/bin/bash", f"{REPO}/scripts/apply-window-rules.sh"], env=env)
    log("restore done")


if __name__ == "__main__":
    main()
