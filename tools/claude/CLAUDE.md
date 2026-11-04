# Rules for every Claude Code session on this Mac

The user works on this Mac while agents run. Never use their screen, mouse, keyboard or their own apps.

- **Web pages** (reading, testing a web app, signing in, forms): the MCP server `browser` (`mcp__browser__*`), a
  headless browser of this session only. Any number of sessions run one at the same time. Sign-ins the user saved
  with `agents-browser login <name> <url>` are already loaded.
- **Desktop apps** (a native app, Finder, an installer): the MCP server `agents-vm` (`mcp__agents-vm__*`), a macOS VM.
  Share files through `~/AgentsShare` (`/Volumes/My Shared Files/AgentsShare` in the VM).
- **Never** open URLs with `open`, script Safari, Zen, Chrome or Helium with `osascript`, simulate keys or clicks
  (`System Events`, `cliclick`), or launch a visible browser from a script. A hook refuses these commands; follow
  its message. Only when the user explicitly asks you to act on their own screen, add `HOST_GUI_OK=1` to the command.
- Headed Playwright or Puppeteer scripts: run them headless.
