#!/usr/bin/env python3
"""Stale Artifact comment monitors of ended Claude Code sessions (docs/bugs.md B23).
A transcript keeps the artifacts whose comment auto-replies were on as "armed" entries of an artifact-comment-monitor
line, and every `claude --resume` tries to restart them. That fails here and the entries stay, so each resume prints
one "Artifact comment monitor ... didn't resume" line per artifact, for good. Appending a line with an empty list drops
them: a later line replaces the armed entries of the earlier ones and keeps the stopped ones. Tested on a real resume
of Claude Code 2.1.316. Sessions still running are never touched, nor entries held by a background job.
session-snapshot.py calls this when a session ends; `claude_monitors.py --all [--dry-run]` sweeps both accounts."""
import glob, json, mmap, os, sys

HOME = os.path.expanduser("~")
ROOTS = (f"{HOME}/.claude", f"{HOME}/.claude-2")
MARK = b'{"type":"artifact-comment-monitor"'
SWEPT = f"{HOME}/.local/state/session-snapshot/monitors-swept.json"


def live_ids():
    ids = set()
    for root in ROOTS:
        for path in glob.glob(f"{root}/sessions/*.json"):
            try:
                s = json.load(open(path))
                os.kill(s["pid"], 0)
                ids.add(s["sessionId"])
            except PermissionError:
                ids.add(s["sessionId"])
            except Exception:
                pass
    return ids


def last_record(path):
    """The last artifact-comment-monitor line, searched from the end (transcripts reach 1 GB)."""
    if not os.path.getsize(path):
        return None
    with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        start = m.rfind(MARK)
        if start < 0:
            return None
        end = m.find(b"\n", start)
        return json.loads(m[start:end if end >= 0 else len(m)])


def clear(path, session_id, dry_run=False):
    """Number of armed entries dropped from this transcript (0: nothing to do)."""
    record = last_record(path)
    entries = (record or {}).get("artifacts") or {}
    armed = [v for v in entries.values() if isinstance(v, dict) and v.get("state") == "armed"]
    if not armed or any("holder" in v for v in armed):
        return 0
    if not dry_run:
        line = json.dumps({"type": "artifact-comment-monitor", "v": 1, "sessionId": session_id, "artifacts": {}},
                          separators=(",", ":"))
        with open(path, "rb") as f:
            f.seek(-1, os.SEEK_END)
            ended = f.read(1) == b"\n"
        with open(path, "ab") as f:
            f.write(("" if ended else "\n").encode() + line.encode() + b"\n")
    return len(armed)


def transcript(root, session_id):
    return next(iter(glob.glob(f"{root}/projects/*/{session_id}.jsonl")), None)


def clear_session(session):
    """One entry of a session-snapshot list."""
    path = transcript(session.get("config") or ROOTS[0], session["sessionId"])
    return clear(path, session["sessionId"]) if path else 0


def clear_ended(sessions, rebooted=False):
    """The sessions of a snapshot that no longer run (after a reboot none does, and their pids may be in use again).
    A transcript is searched once per size: it can hold no such line at all, and an idle Mac keeps the same snapshot
    for hours."""
    try:
        swept = json.load(open(SWEPT))
    except Exception:
        swept = {}
    live = set() if rebooted else live_ids()
    kept = {}
    for s in sessions:
        sid = s["sessionId"]
        if sid in live:
            continue
        path = transcript(s.get("config") or ROOTS[0], sid)
        if not path:
            continue
        size = os.path.getsize(path)
        if swept.get(sid) != size:
            clear(path, sid)
            size = os.path.getsize(path)
        kept[sid] = size
    if kept != swept:
        tmp = SWEPT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(kept, f)
        os.replace(tmp, SWEPT)


def main():
    dry_run = "--dry-run" in sys.argv
    if "--all" not in sys.argv:
        print(__doc__)
        return 2
    live = live_ids()
    for root in ROOTS:
        for path in glob.glob(f"{root}/projects/*/*.jsonl"):
            sid = os.path.basename(path)[:-len(".jsonl")]
            if sid in live:
                continue
            n = clear(path, sid, dry_run)
            if n:
                print(f"{n} armed  {path.replace(HOME, '~')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
