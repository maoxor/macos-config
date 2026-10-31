# BrightIntosh

Lets SDR content use the XDR display's 1000 nits on demand. Uses Apple's public gamma API, macOS keeps control of the
display and still dims it when hot. Open source (GPL-3.0), no Homebrew cask.

- **Install / update:** `tools/brightintosh/build.sh`, pinned tag and commit, source in `~/src/BrightIntosh`. Scheme
  `BrightIntosh` is the free edition: the trial and purchase code only exist in the `STORE` build. Ad hoc signature.
- **Use:** Cmd+F3 (`tools/hammerspoon/config/brightness-boost.lua`), which starts it if needed; no login item. CLI:
  `/Applications/BrightIntosh.app/Contents/MacOS/BrightIntosh cli toggle|enable|disable|status`, app running. Its own
  Cmd+Option+B never reached it here, cause not found (2026-10-31).
- **Network:** nothing automatic; an anonymous diagnostic is sent only if the user accepts it after a failure.
- **Limits:** HDR videos clip while it is on; do not use it for colour work; f.lux and MonitorControl conflict with it,
  Lunar not tested. Open upstream issues: overexposure after sleep on M5 (#279), drop in full-screen video on macOS 27 (#301).
- **Rollback:** quit it and delete `/Applications/BrightIntosh.app`.
