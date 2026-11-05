#!/bin/bash
# Build the patched OmniWM used by this setup and install it as /Applications/OmniWM.app.
#
#   tools/omniwm/build-local.sh            fetch upstream at the pinned commit, apply patches/, build, install
#   tools/omniwm/build-local.sh --check    only verify that the patches apply cleanly (no build, no install)
#
# Source of truth: tools/omniwm/UPSTREAM (pinned upstream commit) + tools/omniwm/patches/*.patch
# (git format-patch series). The working checkout lives in $OMNIWM_SRC (default ~/src/omniwm) on the
# branch "macos-config"; it is recreated from the pin + patches on every run, so never commit there
# by hand: change the patches in this repo instead (see tools/omniwm/README.md, "Changing a patch").
#
# Signing: with the self-signed certificate "$OMNIWM_CERT" (default "OmniWM Local Signing", created
# once by tools/omniwm/create-signing-cert.sh). macOS ties Accessibility and Screen Recording grants
# to the designated requirement (bundle id + certificate leaf), so they survive rebuilds. Never ship an
# ad-hoc signed build: every rebuild would lose the permissions.
# Rollback: the previous build is kept as $BACKUPS/OmniWM-local-prev.app (mv it back).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${OMNIWM_SRC:-$HOME/src/omniwm}"
CERT="${OMNIWM_CERT:-OmniWM Local Signing}"
UPSTREAM_URL="https://github.com/OmniNull/OmniWM.git"
PIN="$(tr -d '[:space:]' < "$HERE/UPSTREAM")"
BACKUPS="${MACOS_CONFIG_STATE:-$HOME/.local/state/macos-power-user-deploy}/backups"

if [ ! -d "$SRC/.git" ]; then
  echo "Cloning upstream OmniWM into $SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone --quiet "$UPSTREAM_URL" "$SRC"
fi
if [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
  echo "$SRC has uncommitted changes: commit or stash them first (nothing was changed)." >&2; exit 2
fi
git -C "$SRC" cat-file -e "$PIN^{commit}" 2>/dev/null || git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet -B macos-config "$PIN"
git -C "$SRC" -c user.name="macos-config" -c user.email="macos-config@localhost" \
  am --quiet --committer-date-is-author-date "$HERE"/patches/*.patch \
  || { git -C "$SRC" am --abort || true; echo "Patches no longer apply on $PIN: rebase them (README)." >&2; exit 1; }
echo "OmniWM source ready: $SRC @ $(git -C "$SRC" rev-parse --short HEAD) (upstream ${PIN:0:8} + $(ls "$HERE"/patches/*.patch | wc -l | tr -d ' ') patches)"
[ "${1:-}" = --check ] && exit 0

hash="$(security find-identity -p codesigning | awk -v n="\"$CERT\"" 'index($0,n){print $2; exit}')"
[ -n "$hash" ] || { echo "Certificate \"$CERT\" missing: run tools/omniwm/create-signing-cert.sh first." >&2; exit 2; }
cd "$SRC"
# Upstream may need a newer Swift than Xcode's (2026-11-05: tools 6.5, Xcode has 6.4): use the toolchain its
# .swift-version names (e.g. main-snapshot-2026-10-11, installed by swiftly) through TOOLCHAINS, which /usr/bin/swift
# honours. The app only links the OS runtime (checked: no symbol from the newer one), so it runs on the current macOS.
if [ -f .swift-version ] && [[ "$(cat .swift-version)" == main-snapshot-* ]]; then
  tc="$HOME/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-$(sed 's/main-snapshot-//' .swift-version)-a.xctoolchain"
  [ -d "$tc" ] || { echo "Swift toolchain missing: swiftly install $(cat .swift-version)" >&2; exit 2; }
  TOOLCHAINS="$(plutil -extract CFBundleIdentifier raw "$tc/Info.plist")"; export TOOLCHAINS
fi
# Upstream's build checks need Python >= 3.11 (tomllib); macOS's /usr/bin/python3 is 3.9: take a newer one from Nix.
if ! python3 -c 'import tomllib' 2>/dev/null; then
  py="$(ls -d /nix/store/*-python3-3.1[1-9]*/bin/python3 2>/dev/null | sort -t- -k3 -V | tail -1)"
  [ -n "$py" ] || { echo "Python >= 3.11 needed (tomllib): none found" >&2; exit 2; }
  PATH="$(dirname "$py"):$PATH"
fi
OMNIWM_SIGNING_IDENTITY="$CERT" Scripts/package-app.sh release dev >/dev/null
app="$SRC/dist/OmniWM.app"
codesign --force --sign "$hash" "$app/Contents/MacOS/omniwmctl"
codesign --force --entitlements "$SRC/OmniWM.entitlements" --sign "$hash" "$app/Contents/MacOS/OmniWM"
codesign --force --entitlements "$SRC/OmniWM.entitlements" --sign "$hash" "$app"
codesign --verify "$app"
codesign -dr - "$app" 2>&1 | grep -q "certificate leaf = H\"$(echo "$hash" | tr 'A-F' 'a-f')\"" \
  || { echo "Designated requirement does not pin the certificate: aborting." >&2; exit 1; }
# Copy first (same volume as /Applications, outside it so LaunchServices does not see a second
# OmniWM), then swap by rename: there is never a moment without an app, and the previous build is
# kept for rollback.
mkdir -p "$BACKUPS"
stage="$BACKUPS/OmniWM-staging.app"; prev="$BACKUPS/OmniWM-local-prev.app"
rm -rf "$stage" && ditto "$app" "$stage"
pkill -x OmniWM || true; sleep 2
rm -rf "$prev"
[ -d /Applications/OmniWM.app ] && mv /Applications/OmniWM.app "$prev"
mv "$stage" /Applications/OmniWM.app
open -g -a OmniWM
echo "Installed /Applications/OmniWM.app (signed by \"$CERT\"); previous build: $prev"
