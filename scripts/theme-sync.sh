#!/bin/bash
# Align the theme with the wallpaper.
#   scripts/theme-sync.sh            copy the wallpaper macOS shows to wallpapers/actuel.png, then apply
#   scripts/theme-sync.sh --no-copy  apply the palette of home-manager/palette.nix without changing the image
# home-manager/palette.nix is regenerated from the image by scripts/palette-from-image.py (distinct accents).
# OmniWM hot-reloads settings.toml, so it is never quit (no AppleScript, hence no Automation permission).
. "$(dirname "$0")/lib.sh"
set -e
if [ "${1:-}" != --no-copy ]; then
  src="$(python3 -I - "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" <<'PY'
import plistlib, re, sys, urllib.parse
d = plistlib.load(open(sys.argv[1], "rb"))
def walk(o):
    if isinstance(o, dict):
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)
    elif isinstance(o, bytes):
        try: yield from walk(plistlib.loads(o))
        except Exception:
            for m in re.findall(rb"file://[^\x00\"<]+", o): yield m.decode("utf-8", "replace")
    elif isinstance(o, str) and o.startswith("file://"): yield o
urls = [u for u in walk(d) if re.search(r"\.(png|jpe?g|heic|tiff?)$", u, re.I)]
print(urllib.parse.unquote(urls[0][7:]) if urls else "")
PY
)"
  [ -n "$src" ] && [ -f "$src" ] || { echo "Current wallpaper file not found (dynamic or system wallpaper?)." >&2; exit 2; }
  tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
  tmpimg="$tmpdir/w.png"; sips -s format png "$src" --out "$tmpimg" >/dev/null
  if cmp -s "$tmpimg" "$REPO/wallpapers/actuel.png"; then echo "wallpaper: unchanged"
  else cp "$tmpimg" "$REPO/wallpapers/actuel.png"; echo "wallpaper: copied from $src"; fi
  # The screen saver (Photos, folder ~/Pictures/Veille) shows the current wallpaper, not Apple's default aerial.
  mkdir -p "$HOME/Pictures/Veille" && cmp -s "$tmpimg" "$HOME/Pictures/Veille/fond.png" || cp "$tmpimg" "$HOME/Pictures/Veille/fond.png"
  # A wallpaper seen before gets back the palette it had (home-manager/palettes/<sha256 of the image>.nix):
  # a later change of the generator never alters the theme of an image already validated.
  saved="$REPO/home-manager/palettes/$(shasum -a 256 "$src" | cut -c1-64).nix"
  if [ -f "$saved" ]; then cp "$saved" "$REPO/home-manager/palette.nix"; echo "palette: saved one for this wallpaper"
  else
    python3 -I "$REPO/scripts/palette-from-image.py" "$REPO/wallpapers/actuel.png" "$REPO/home-manager/palette.nix" "wallpaper (auto)"   # neutral name: no personal file name in commits
    mkdir -p "$(dirname "$saved")"; cp "$REPO/home-manager/palette.nix" "$saved"
  fi
  ( cd "$REPO" && git add home-manager/palettes )
fi
# Ghostty first (about a second), then the build that makes it permanent and themes everything else.
python3 -I "$REPO/scripts/ghostty-live-colors.py" "$REPO/home-manager/palette.nix" || true
# The flake only sees files git knows: stage the theme files, and only those (never unrelated work).
( cd "$REPO" && git add home-manager/palette.nix )   # wallpapers/ stays local (.gitignore)
"$REPO/scripts/apply.sh" home-manager --write | tail -1
"$REPO/scripts/theme-apply.sh" --write
cp -p "$HOME/.config/omniwm/settings.toml" "$STATE/backups/omniwm-$(date +%Y%m%d-%H%M%S)-theme-sync.toml"
python3 -I "$REPO/tools/omniwm/apply-registry.py" "$HOME/.config/omniwm/settings.toml" --write </dev/null | tail -1  # hot-reloaded by OmniWM
hs=/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs
( "$hs" -c 'hs.timer.doAfter(0.2, function() local g=hs.application.get("com.mitchellh.ghostty"); if g then g:selectMenuItem({"Ghostty","Reload Configuration"}) end; hs.reload() end)' & p=$!; sleep 4; kill $p ) >/dev/null 2>&1 || true
echo "Theme applied. Review, then capture: scripts/capture.sh && scripts/capture.sh --accept; commit."
