#!/bin/bash
# DRIFT CHECK (read-only): does this Mac still match the repo?
#   scripts/verify.sh         configs, Brewfile, macOS settings, screen edges
#   scripts/verify.sh --hm    also: the active Home Manager generation = what the flake builds
# Exit 0 = no drift. Fix a drift with scripts/capture.sh (machine -> repo) or scripts/apply.sh (repo -> machine).
# Scope: only what this setup manages (tools/configs.tsv, homebrew/Brewfile, scripts/macos-defaults.sh);
# your other apps are none of its business.
. "$(dirname "$0")/lib.sh"
rc=0; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "== Configs (machine vs repo, tools/configs.tsv)"
while IFS=$'\t' read -r id type live dest _ _; do
  if ! live_copy "$tmp/cur" "$type" "$live"; then echo "  missing  $id  $live  (scripts/apply.sh $id --write)"; rc=1; continue; fi
  if cmp -s "$tmp/cur" "$REPO/$dest"; then echo "  ok       $id  $dest"
  else echo "  DRIFT    $id  $dest  (diff: scripts/capture.sh)"; rc=1; fi
done < <(config_rows)

echo "== Homebrew (apps of homebrew/Brewfile installed)"
# Missing = drift. Outdated is only reported: apply installs with --no-upgrade, and an upgrade can cost an app its
# Accessibility permission (Neru), so upgrades stay a decision (brew upgrade --cask <app>).
if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --no-upgrade --file="$REPO/homebrew/Brewfile" >/dev/null 2>&1; then
  echo "  ok"
  old="$(HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --verbose --file="$REPO/homebrew/Brewfile" 2>&1 \
    | sed -n 's/^→ [A-Za-z]* \([^ ]*\) needs to be installed or updated\./\1/p' | tr '\n' ' ')"
  [ -n "$old" ] && echo "  info  newer versions available: $old"
else echo "  DRIFT    missing (scripts/apply.sh homebrew --write)"; rc=1; fi

echo "== macOS settings (scripts/macos-defaults.sh)"
if "$REPO/scripts/macos-defaults.sh" >/dev/null; then echo "  ok"; else echo "  DRIFT    (scripts/macos-defaults.sh to see, --write to fix)"; rc=1; fi

echo "== Screen edges (docs/bugs.md B6)"
if pgrep -x Hammerspoon >/dev/null; then
  if out="$("$REPO/tools/hammerspoon/check-margin-veil.sh")"; then echo "  ok"; else echo "$out" | sed 's/^/  /'; rc=1; fi
else echo "  skipped: Hammerspoon is not running"; fi

if [ "${1:-}" = --hm ]; then
  echo "== Home Manager"
  out="$(cd "$REPO/home-manager" && MACOS_CONFIG_REPO="$REPO" nix build --impure '.#homeConfigurations.mac.activationPackage' --no-link --print-out-paths 2>/dev/null)"
  active="$(readlink -f "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null)"
  if [ -n "$out" ] && [ "$out" = "$active" ]; then echo "  ok       active generation = flake"
  else echo "  DRIFT    flake=$out active=$active (scripts/apply.sh home-manager --write)"; rc=1; fi
fi
exit "$rc"
