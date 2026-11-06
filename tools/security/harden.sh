#!/bin/bash
# System hardening that needs root (run: sudo tools/security/harden.sh). Idempotent; README.md lists each setting.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
$FW --setglobalstate on >/dev/null
$FW --setstealthmode on >/dev/null                      # no answer to ping/port probes (public Wi-Fi)
# Touch ID for sudo; sudo_local survives macOS updates (unlike /etc/pam.d/sudo)
printf '%s\n' '# sudo_local: local config file which survives system update and is included for sudo' \
  'auth       sufficient     pam_tid.so' > /etc/pam.d/sudo_local
chmod 444 /etc/pam.d/sudo_local
# Updates: check, download, install security responses and system data; macOS upgrades stay manual (Nix /etc hooks)
SU=/Library/Preferences/com.apple.SoftwareUpdate
defaults write $SU AutomaticCheckEnabled -bool true
defaults write $SU AutomaticDownload -bool true
defaults write $SU CriticalUpdateInstall -bool true
defaults write $SU ConfigDataInstall -bool true
defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true
# SSH (Remote Login stays on for emergencies, docs/recovery.md): keys only, no root. 000- so it wins over 100-macos.conf
cat > /etc/ssh/sshd_config.d/000-hardening.conf <<C
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
MaxAuthTries 3
C
chmod 644 /etc/ssh/sshd_config.d/000-hardening.conf
/usr/sbin/sshd -t
echo "OK: firewall stealth, Touch ID sudo, auto security updates, SSH keys only."
