# Security hardening

Audit of 2026-11-06 (macOS 26.6, M5 Max). References: macOS 26 Tahoe hardening guide (insinuator.net, Feb 2026),
drduh/macOS-Security-and-Privacy-Guide, Objective-See tools.

| Setting | Where |
|---|---|
| FileVault, Gatekeeper, firewall | already on |
| Firewall stealth mode | `harden.sh` (root) |
| Touch ID for sudo (`/etc/pam.d/sudo_local`) | `harden.sh` |
| Automatic security responses, system data, App Store updates (macOS upgrades stay manual: Nix hooks in /etc) | `harden.sh` |
| SSH: keys only, no root, 3 tries (`/etc/ssh/sshd_config.d/000-hardening.conf`); Remote Login stays on for `docs/recovery.md` | `harden.sh` |
| AirPlay receiver off (ports 5000/7000) | `home-manager/macos.nix` |
| LuLu, BlockBlock, OverSight, KnockKnock | `homebrew/Brewfile` (`askpass.sh` gives brew's sudo a password dialog) |

Install: `osascript -e 'do shell script "<repo>/tools/security/harden.sh" with administrator privileges'`, then
`SUDO_ASKPASS=<repo>/tools/security/askpass.sh brew bundle --file homebrew/Brewfile`.

User only (cannot be scripted): SIP is **off** and nothing in this config needs it off (OmniWM README: "SIP stays
enabled"; no yabai, no scripting addition): Recovery → Terminal → `csrutil enable`. Lock screen "Require password"
→ Immediately (System Settings → Lock Screen). LuLu's network extension approval.
