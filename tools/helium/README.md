# Helium

Development browser since 2026-11-03 (Chromium engine; Zen is the main browser, Safari stays for WebKit checks).
Open source (imput), no Google account or telemetry, uBlock Origin built in, Chrome Web Store extensions.

- **Install:** Homebrew cask `helium-browser`. Settings are personal (profile in `~/Library/Application Support/net.imput.helium`).
- **Workspace:** OmniWM rule → workspace 4 Atelier, tiled (`tools/omniwm/config/settings.toml`).
- **Tabs:** Cmd+← / Cmd+→ = previous / next tab outside text fields (Hammerspoon `safari-tabs.lua`, same keys as Zen and Safari).
- **Not a test browser:** Playwright's own Chromium and Chrome for Testing stay on workspace 4 through `test-browsers.lua`;
  Helium (`net.imput.helium`) is the user's and keeps the keyboard.
- **Rollback:** `brew uninstall --cask helium-browser`, remove its OmniWM rule.
