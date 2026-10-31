# BrightIntosh

Lets SDR content use the XDR display's 1000 nits on demand. Uses Apple's public gamma API, macOS keeps control of the
display and still dims it when hot. Open source (GPL-3.0), no Homebrew cask.

- **Install / update:** `tools/brightintosh/build.sh`, pinned tag and commit, source in `~/src/BrightIntosh`. Scheme
  `BrightIntosh` is the free edition: the trial and purchase code only exist in the `STORE` build. Ad hoc signature.
- **Start:** by hand, no login item. It must be running for its shortcuts. The menu bar is hidden here, so use them.
- **Shortcuts:** Cmd+Option+B on / off, Cmd+Option+N / M more / less, Cmd+Option+Shift+B settings.
- **Network:** nothing automatic; an anonymous diagnostic is sent only if the user accepts it after a failure.
- **Limits:** HDR videos clip while it is on; do not use it for colour work; f.lux and MonitorControl conflict with it,
  Lunar not tested. Open upstream issues: overexposure after sleep on M5 (#279), drop in full-screen video on macOS 27 (#301).
- **Rollback:** quit it and delete `/Applications/BrightIntosh.app`.
