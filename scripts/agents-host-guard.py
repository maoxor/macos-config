#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash): agents never drive the user's own apps. Refuses a command that opens or scripts
the user's browsers or simulates input on the user's screen, and says what to use instead: the MCP server "browser"
(a headless browser per session, any number in parallel) or "agents-vm" (a macOS desktop of their own).

Checked: the command itself, and the script files it runs (plus the modules they import from their own folder),
since a Python helper calling osascript hid the Safari driving of 2026-11-04. Escape hatch for a task where the user
explicitly asked to act on their screen: put HOST_GUI_OK=1 in the command. It counts only if the user's latest message
in the session's transcript names the screen or one of their apps (an agent cannot grant it to itself), and every
use is logged. Fails open (any error = allowed).
Log of refusals: ~/Library/Logs/macos-config/agents-host-guard.log"""
import json, os, re, sys, time

BROWSERS = r"(Safari|Zen|Zen Browser|Google Chrome|Chrome|Chromium|Helium|Firefox|Arc|Brave Browser|Microsoft Edge)"
RULES = [
    (re.compile(r"""tell\s+(application|app)\s+(id\s+)?\\?["']?""" + BROWSERS + r"""\b""", re.I), "scripts a browser of the user"),
    (re.compile(r"""tell\s+(application|app)\s+\\?["']?System Events\\?["']?.{0,400}\b(keystroke|key code|click)\b""", re.I | re.S),
     "simulates keys or clicks on the user's screen"),
    (re.compile(r"""(^|[;&|(\s])open\s+(-[a-zA-Z]+\s+)*(-a\s+["']?""" + BROWSERS + r"""|-b\s+\S*(safari|zen|chrome|helium|firefox)|["']?https?://)""", re.I),
     "opens a page in a browser of the user"),
    (re.compile(r"""\b(cliclick|xdotool)\b"""), "simulates input on the user's screen"),
    # A visible browser started by an agent (CDP / remote debugging): 2026-11-04 a session's Chrome window took the
    # front. Allowed with --headless.
    (re.compile(r"""^(?![\s\S]*--headless)[\s\S]*(Google Chrome\.app/Contents/MacOS/Google Chrome|Chromium\.app/Contents/MacOS/Chromium|\bopen\s+(-\w+\s+)*-n?a\s+["']?(Google Chrome|Chromium)["']?.*--args|--remote-debugging-port)""", re.I),
     "starts a visible browser window (add --headless)"),
    (re.compile(r"""webbrowser\.open|subprocess\.\w+\(\s*\[\s*["']open["']\s*,\s*["']https?://""", re.I), "opens a page in a browser of the user"),
]
HINT = ("Do not use the user's own browser or screen: they are working. For web pages use the MCP server 'browser' "
        "(mcp__browser__*: a headless browser of your own, sign-ins from `agents-browser login`); for desktop apps use "
        "'agents-vm' (mcp__agents-vm__*: a macOS VM). Only if the user explicitly asked you to act on their screen, "
        "add HOST_GUI_OK=1 to the command.")
SCRIPT_RE = re.compile(r"""(?:^|\s)([^\s'";|&<>]+\.(?:py|sh|js|mjs|ts|applescript|scpt|rb))\b""")


def expand(cmd):
    """Substitute variables assigned in the command itself (S=/path; python3 $S/x.py), then the environment's."""
    env = dict(os.environ)
    for name, value in re.findall(r"""(?:^|[;&\s])([A-Za-z_]\w*)=("[^"]*"|'[^']*'|[^\s;&|]+)""", cmd):
        env[name] = os.path.expanduser(value.strip("'\""))
    return re.sub(r"\$\{?([A-Za-z_]\w*)\}?", lambda m: env.get(m.group(1), m.group(0)), cmd)


def log(msg):
    try:
        with open(os.path.expanduser("~/Library/Logs/macos-config/agents-host-guard.log"), "a") as f:
            f.write(f"{time.strftime('%F %T')} {msg}\n")
    except OSError:
        pass


def scripts_of(cmd, cwd):
    seen, out = set(), []
    for m in SCRIPT_RE.finditer(expand(cmd)):
        p = os.path.expanduser(m.group(1))
        p = p if os.path.isabs(p) else os.path.join(cwd, p)
        if os.path.isfile(p) and p not in seen:
            seen.add(p); out.append(p)
    for p in list(out):  # modules imported from the script's own folder (one level)
        try:
            text = open(p, errors="replace").read(400_000)
        except OSError:
            continue
        for mod in re.findall(r"^\s*(?:from|import)\s+([A-Za-z_]\w*)", text, re.M):
            q = os.path.join(os.path.dirname(p), mod + ".py")
            if os.path.isfile(q) and q not in seen:
                seen.add(q); out.append(q)
    return out


USER_ASKS = re.compile(r"\b(écran|ecran|screen|fenêtre|fenetre|window|onglet|tab|safari|zen|chrome|helium|raycast|"
                       r"finder|souris|mouse|clavier|keyboard|mon (navigateur|mac|ordinateur)|host_gui_ok)\b", re.I)


def last_user_text(transcript):
    """The user's latest typed message in a Claude Code transcript (tool results excluded)."""
    last = ""
    try:
        with open(transcript, errors="replace") as f:
            for line in f:
                if '"type":"user"' not in line.replace(" ", ""):
                    continue
                o = json.loads(line)
                content = (o.get("message") or {}).get("content")
                if isinstance(content, str):
                    last = content
                elif isinstance(content, list):
                    texts = [c.get("text", "") for c in content if c.get("type") == "text"]
                    if texts and not any(c.get("type") == "tool_result" for c in content):
                        last = "\n".join(texts)
    except (OSError, ValueError):
        pass
    return last


def verdict(text, command=False):
    for i, (rx, why) in enumerate(RULES):
        if command and i < 2 and "osascript" not in text:
            continue  # AppleScript in a command line only runs through osascript ("echo 'tell application …'" is text)
        if rx.search(text):
            return why
    return None


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    escape = "HOST_GUI_OK=1" in cmd
    if escape:
        asked = USER_ASKS.search(last_user_text(data.get("transcript_path") or ""))
        log(f"escape {'accepted' if asked else 'REFUSED (latest user message does not name the screen or an app)'} "
            f"cwd={data.get('cwd')} cmd={cmd[:200]!r}")
        if asked:
            return
    why, where = verdict(cmd, command=True), "command"
    if not why:
        for p in scripts_of(cmd, data.get("cwd") or os.getcwd()):
            try:
                why = verdict(open(p, errors="replace").read(400_000))
            except OSError:
                continue
            if why:
                where = p
                break
    if not why:
        return
    log(f"refused ({why}, in {where}) cwd={data.get('cwd')} cmd={cmd[:300]!r}")
    json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                      "permissionDecisionReason": f"Refused: this {where} {why}. {HINT}"}}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # fail open: a broken guard must never block work
