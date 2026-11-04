# Agents VM

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
