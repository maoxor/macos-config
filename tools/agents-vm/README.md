# Agents: browser, VM and guard

Every Claude Code session works without touching the user's screen, mouse, keyboard or own apps (2026-11-04):

| Need | Tool | Parallel |
|---|---|---|
| Web pages (read, test a web app, sign in, forms, screenshots) | MCP `browser` = `scripts/agents-browser`: Playwright MCP 0.0.83 (pinned, `~/.local/share/agents-browser`), **headless, isolated**, Chromium (`agents-browser mcp webkit` = Safari's engine) | one browser per session, no limit (6 at once measured: 10 s, host untouched) |
| Desktop apps | MCP `agents-vm` (below) | 2 macOS VMs at once (Apple) |
| Guard | `scripts/agents-host-guard.py`, PreToolUse hook (Bash) in `~/.claude` and `~/.claude-2` settings: refuses `open <url>`, `open -a <browser>`, osascript to a browser or System Events keys, cliclick, a visible Chrome/Chromium launch (CDP; allowed with --headless), and the same inside the scripts a command runs (plus their local imports) | — |
| Rules | `tools/claude/CLAUDE.md` linked as `~/.claude/CLAUDE.md` and `~/.claude-2/CLAUDE.md` | — |

- Sign-ins: `agents-browser login default <url>` (the user signs in once in a visible window); `state/default.json` is
  copied into each session (isolated: sessions never share or overwrite it). `agents-browser states` lists them.
- Escape hatch: `HOST_GUI_OK=1` in a command, accepted only if the user's latest message in that session names the
  screen or one of their apps (an agent cannot grant it to itself). Refusals and escapes:
  `~/Library/Logs/macos-config/agents-host-guard.log`.
- Why: on 2026-11-04 a session (~/dev/ideas) drove the user's Safari through a Python helper (`outils_safari.py`) to
  test a Jira app; window-journal showed only Safari (LaunchServices), the transcripts showed the script.
- Measured: an agent asked to "check the page with a screenshot" used `mcp__browser__*` by itself; no window, no
  Safari tab, front app unchanged. An agent told to "open it in Safari with open" added HOST_GUI_OK=1 itself
  and got through (before the escape was tightened): hence the transcript check, tested on both cases.
- Limits: the guard reads commands and the scripts they name; code downloaded and run in other ways is not inspected.
  Playwright scripts an agent writes itself should run headless (rule in CLAUDE.md; `playwright-watch` already keeps
  headed test pages behind the user's windows).

## Agents VM

A macOS virtual machine where AI agents (Claude Code, and any MCP client such as Codex) use a real desktop — apps,
browser, files, terminal — in the background. The user's screen, mouse and keyboard are never touched: the agent
clicks and types inside the VM. Built 2026-11-04.

| Piece | What |
|---|---|
| VM | Lume (Cua, MIT, Homebrew `lume`), Apple's Virtualization.framework. VM `agents`: macOS 26.6, 6 CPU, 12 GB, 120 GB sparse disk (~25 GB used), 1920×1200, NAT |
| Clean copy | `agents-base` (stopped, APFS clone, no extra disk): source for a reset or a second VM |
| Agent control | Cua Driver (MIT) inside the VM, signed release, SHA-256 checked by its installer; Accessibility + Screen Recording granted to it in the guest only |
| Bridge | `agents-vm mcp` = SSH (host key in `~/.ssh/known_hosts_agents`, the host's public key in the guest) to `cua-driver mcp` |
| Claude Code | `claude mcp add -s user agents-vm -- ~/.local/bin/agents-vm mcp`; `MCP_TIMEOUT=120000` in `~/.claude/settings.json` (a cold VM start takes ~16 s) |
| Shared folder | host `~/AgentsShare` = guest `/Volumes/My Shared Files/AgentsShare` (read-write) |
| Telemetry | off in both: `lume config telemetry disable`, `cua-driver telemetry disable` + `reset-id` |

## Use
- Ask Claude Code to work "in the agents VM" (tools `mcp__agents-vm__*`): it starts the VM if needed.
- Watch or take over: Raycast **VM des agents**, or `agents-vm view` (Lume's viewer window).
- `agents-vm status | up | down | shot [file] | ssh [cmd] | new <name>`.
- Guest account: `lume` / `lume` (local to the VM; no Apple account, no personal data, FileVault off so it logs in
  by itself). Sign in to sites inside the VM only on purpose, with accounts meant for agents.

## Measured (2026-11-04)
- A headless `claude -p` task (open TextEdit in the VM, type a sentence, check it with a capture) succeeded; during it
  the host pointer and the frontmost app did not change once (13 samples, every 2 s).
- MCP connect: 16 s from a stopped VM, 3 s when it runs.

## Several agents
- One VM: Cua Driver acts in the background (by accessibility element, apps launched without coming to the front),
  so agents on different apps can share it; two agents on the same app will collide.
- A second VM: `agents-vm new agents-2`, then `claude mcp add -s user agents-vm-2 -e AGENTS_VM=agents-2 --
  ~/.local/bin/agents-vm mcp`. Apple's licence allows **2 macOS VMs running at once** per Mac; each needs ~12 GB RAM.
- More in parallel: Linux desktops in containers (Anthropic's computer-use image, noVNC) — not set up yet.

## Pitfalls met
- Over SSH, `screencapture` has no display and `osascript` to an app waits on an Automation prompt: go through
  Cua Driver (`agents-vm shot`), or `pkill` an app instead of quitting it by AppleScript.
- `python3` in the guest opens the Command Line Tools installer: parse on the host.
- First boot showed Setup Assistant screens (updates, Apple account: skipped, analytics: off, FileVault: off).
- Granting Screen Recording on Tahoe needed the "+" button (CuaDriver.app) then "Allow" on the direct-capture prompt.

## Reset / remove
- Reset: `lume stop agents; lume delete agents; lume clone agents-base agents`.
- Remove: `claude mcp remove -s user agents-vm`, `lume delete agents agents-base`, drop `brew "lume"` and the
  `agents-vm` line in `home-manager/startup.nix`, `scripts/apply.sh home-manager --write`.
