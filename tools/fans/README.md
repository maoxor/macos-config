# Fans and energy mode

Menu bar item **fan** (SketchyBar, stats pill): current mode and the fastest fan's speed; click for the modes.

| Mode | Energy (`pmset powermode`) | Fans |
|---|---|---|
| Automatique | automatic | macOS |
| Économie | Low Power | macOS |
| Équilibré | automatic | ramp 50 → 90 °C (earlier than Apple) |
| Performance | High Power | ramp 45 → 80 °C, floor 40 % |
| Maximum | High Power | full speed |

- **How:** the item writes the mode to `~/.local/state/fanctl/mode`; the root LaunchDaemon `io.maoxor.fanctl`
  (`fanctl-daemon.sh`) applies it every 3 s, with the hottest of CPU/GPU from macmon and Stats' `smc` tool. Free, no
  third-party fan app. Root-owned copies of both binaries in `/usr/local/libexec/fanctl`.
- **Control:** averaged temperature (~12 s), up at once and down by 4 %/step after a 3 °C drop (hysteresis), full speed at 95 °C; target rewritten every 3 s (macOS takes manual fans back, sleep resets them). M5: mode key `F<n>md`, no Ftst unlock.
- **Fail-safe:** on stop, unknown mode or no temperature, the fans return to automatic and the energy mode to automatic.
- **Install (admin, by the user):** `sudo tools/fans/install.sh`; rerun after changing the daemon or updating Stats/macmon.
  Remove: `sudo tools/fans/install.sh --uninstall`. Without the daemon, a mode other than Auto shows "?" in red.
