#!/bin/bash
# DIAGNOSTIC (read-only): is every component of this setup installed, configured and working?
#   scripts/doctor.sh        one line per check: ok / WARN / FAIL, with the fix to run
# Exit 0 = no FAIL. Complements scripts/verify.sh (machine <-> repo drift) and scripts/check.sh
# (offline repo checks). Safe to run any time; it never writes.
. "$(dirname "$0")/lib.sh"
fails=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n        -> %s\n' "$1" "$2"; }
fail() { printf '  FAIL  %s\n        -> %s\n' "$1" "$2"; fails=$((fails + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }
HS=/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs
CTL=/Applications/OmniWM.app/Contents/MacOS/omniwmctl

echo "== Machine"
[ "$(uname -m)" = arm64 ] && ok "Apple Silicon" || fail "not Apple Silicon ($(uname -m))" "this setup targets arm64 Macs only"
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] && ok "macOS $(sw_vers -productVersion)" || warn "macOS $(sw_vers -productVersion)" "built and tested on macOS 26; older versions are untested"
xcode-select -p >/dev/null 2>&1 && ok "Xcode command line tools" || fail "Xcode command line tools missing" "xcode-select --install"
[ -d /Applications/Xcode.app ] && ok "Xcode (needed to build OmniWM)" || fail "Xcode.app missing" "install Xcode from the App Store, open it once, then: sudo xcode-select -s /Applications/Xcode.app"

echo "== Package managers"
have brew && ok "Homebrew $(brew --version | head -1 | cut -d' ' -f2)" || fail "Homebrew missing" "see README: Install"
if have nix; then ok "$(nix --version | head -1)"; else fail "Nix (Lix) missing" "see README: Install"; fi
gen="$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null)"
[ -n "$gen" ] && ok "Home Manager generation active" || fail "no Home Manager generation" "scripts/apply.sh home-manager --write"
for c in rg fzf zoxide jq starship fd gh atuin; do have "$c" || fail "$c not on PATH" "open a new terminal; else scripts/apply.sh home-manager --write"; done
# Missing apps only: a newer version is not a fault (apply uses --no-upgrade; verify.sh lists them).
HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --no-upgrade --file="$REPO/homebrew/Brewfile" >/dev/null 2>&1 && ok "Brewfile satisfied" || warn "Brewfile not fully installed" "scripts/apply.sh homebrew --write"

echo "== Identity"
[ "$(cat "$HOME/.config/macos-config/repo" 2>/dev/null)" = "$REPO" ] && ok "$HOME/.config/macos-config/repo" || fail "$HOME/.config/macos-config/repo missing or stale" "./install.sh (step identity)"

echo "== OmniWM"
if [ -d /Applications/OmniWM.app ]; then
  if codesign -dr - /Applications/OmniWM.app 2>&1 | grep -q "certificate leaf"; then ok "OmniWM.app signed with a stable certificate"
  else fail "OmniWM.app is ad-hoc or upstream-signed" "tools/omniwm/create-signing-cert.sh && tools/omniwm/build-local.sh"; fi
else fail "OmniWM.app missing" "tools/omniwm/create-signing-cert.sh && tools/omniwm/build-local.sh"; fi
if pgrep -x OmniWM >/dev/null; then
  if q="$(timeout 5 "$CTL" query workspaces 2>/dev/null)" && echo "$q" | grep -q '"ok" : true'; then
    ok "OmniWM running, IPC answers"
    echo "$q" | grep -q '"layout" : "niri"' && ok "Niri workspaces present" || warn "no Niri workspace" "settings: workspaces 2-9 layoutType = \"niri\" (tools/omniwm/config/settings.toml)"
  else fail "OmniWM running but IPC silent" "Accessibility permission? System Settings > Privacy > Accessibility > OmniWM"; fi
else fail "OmniWM not running" "open -a OmniWM (LaunchAgent org.nix-community.home.omniwm starts it at login)"; fi
if pgrep -x memory-guard >/dev/null; then ok "memory guard running (docs/bugs.md B21)"
else fail "memory guard not running: nothing stops a memory exhaustion panic" "launchctl kickstart -k gui/$(id -u)/org.nix-community.home.memory-guard; log: ~/Library/Logs/macos-config/memory-guard.log"; fi
[ -x "$HOME/.local/bin/xdr-boost" ] && ok "XDR boost installed" || warn "XDR boost missing" "scripts/apply.sh home-manager --write"
n="$(python3 -I "$REPO/tools/omniwm/apply-registry.py" "$HOME/.config/omniwm/settings.toml" 2>/dev/null | tail -1)"
case "$n" in "0 change(s)") ok "settings.toml matches the registry";; *) warn "settings.toml differs from the registry ($n)" "quit OmniWM; python3 -I tools/omniwm/apply-registry.py ~/.config/omniwm/settings.toml --write";; esac
"$REPO/scripts/macos-defaults.sh" >/dev/null && ok "macOS settings (gestures, Dock, Finder)" || warn "macOS settings differ" "scripts/macos-defaults.sh (preview) then --write"

echo "== Hammerspoon"
if pgrep -x Hammerspoon >/dev/null && [ -x "$HS" ]; then
  r="$(timeout 8 "$HS" -c 'return tostring(hs.accessibilityState())..","..tostring(wsHide~=nil)..","..tostring(marginVeil~=nil)..","..tostring(axGuard~=nil)' </dev/null 2>/dev/null | tail -1)"
  case "$r" in
    true,true,true,true) ok "Hammerspoon: Accessibility + ws-hide, margin-veil, ax-guard loaded";;
    "") fail "Hammerspoon IPC silent" "open Hammerspoon once; check ~/.hammerspoon/init.lua (scripts/apply.sh hammerspoon --write)";;
    *) fail "Hammerspoon modules/permission: $r (accessibility,ws-hide,margin-veil,ax-guard)" "scripts/apply.sh hammerspoon --write; grant Accessibility";;
  esac
  "$REPO/tools/hammerspoon/check-margin-veil.sh" >/dev/null 2>&1 && ok "screen-edge veil" || warn "screen-edge veil check failed" "tools/hammerspoon/check-margin-veil.sh"
else fail "Hammerspoon not running" "open -a Hammerspoon"; fi

echo "== Other components"
for app in Ghostty Neru Raycast Stats; do
  [ -d "/Applications/$app.app" ] && ok "$app installed" || warn "$app not installed" "scripts/apply.sh homebrew --write"
done
[ -f "$HOME/.config/ghostty/config" ] && ok "Ghostty config present" || warn "no Ghostty config" "scripts/apply.sh home-manager --write (Stylix writes it)"
pgrep -ix neru >/dev/null && ok "Neru running" || warn "Neru not running" "open -a Neru; grant Accessibility"

echo "== macOS services"
# Safari retried this disabled Quick Note service ~1/s; each retry could block its rendering ~500 ms
# while windows moved (docs/bugs.md B18). Other disabled Apple services had no measured effect.
if launchctl print-disabled "gui/$(id -u)" 2>/dev/null | grep -q '"com.apple.synapse.contentlinkingd" => disabled'; then
  fail "com.apple.synapse.contentlinkingd disabled (Safari freezes while windows move)" \
    "launchctl enable gui/$(id -u)/com.apple.synapse.contentlinkingd; launchctl bootstrap gui/$(id -u) /System/Library/LaunchAgents/com.apple.synapse.contentlinkingd.plist"
else ok "Quick Note link service (contentlinkingd) enabled"; fi

echo
[ "$fails" = 0 ] && echo "doctor: no failure." || echo "doctor: $fails failure(s)."
[ "$fails" = 0 ]
