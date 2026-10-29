#!/bin/bash
# Run by the launchd agent "theme-auto" whenever macOS rewrites its wallpaper index.
# If the displayed image really changed: regenerate the palette, apply the theme, capture and commit only
# the theme files, then notify. Otherwise do nothing.
# Log: ~/Library/Logs/macos-config/theme-auto.log   Disable: launchctl bootout gui/$(id -u)/org.nix-community.home.theme-auto
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
REPO="$(cd "$(dirname "$0")/.." && pwd)"   # the clone this script lives in
LOCK="${TMPDIR:-/tmp}/macos-config-theme-auto.lock"
exec >>"$HOME/Library/Logs/macos-config/theme-auto.log" 2>&1
# Lock = directory holding the PID: a run killed by SIGKILL (logout) must not block all later runs.
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then echo "$(date '+%F %T') already running, skipped"; exit 0; fi
  echo "$(date '+%F %T') stale lock removed"; rm -rf "$LOCK"; mkdir "$LOCK" || exit 0
fi
echo $$ > "$LOCK/pid"
IDX="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
# macOS rewrites the index on every wake/unlock (LastUse timestamps only): fingerprint the index without
# them (~40 ms) and stop before the 3 s wait and the Python parse when unchanged. The whole index, not
# AllSpacesAndDisplays.Desktop: a wallpaper chosen per display lives under Displays.<uuid>.Desktop, and the
# missing key once gave a constant fingerprint that skipped every change (2026-10-21).
FP="$HOME/.local/state/macos-power-user-deploy/theme-auto.fingerprint"
fp="$(plutil -convert xml1 -o - "$IDX" 2>/dev/null | sed '/<key>LastUse<\/key>/{N;d;}' | shasum | cut -c1-40)"
if [ "$fp" != "da39a3ee5e6b4b0d3255bfef95601890afd80709" ] && [ "$fp" = "$(cat "$FP" 2>/dev/null)" ]; then rm -rf "$LOCK"; exit 0; fi
start_mtime="$(stat -f %m "$IDX")"
# launchd does not queue a change that happens while this runs: check again on exit.
rerun_if_changed() { rm -rf "$LOCK"; [ "$(stat -f %m "$IDX")" != "$start_mtime" ] && { echo "$(date '+%F %T') index changed during the run: running again"; exec /bin/bash "$0"; }; }
trap rerun_if_changed EXIT
sleep 1  # let macOS finish writing the index
# Every Space shows the same wallpaper (macOS keeps an older choice per Space, seen on the lock screen).
python3 -I "$REPO/scripts/wallpaper-all-spaces.py"

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
[ -n "$src" ] && [ -f "$src" ] || { echo "$(date '+%F %T') wallpaper without an image file (dynamic/system): skipped"; exit 0; }
sum="$(shasum -a 256 "$src" | cut -c1-64)"
[ "$sum" = "$(cat "$REPO/wallpapers/source.sha256" 2>/dev/null)" ] && { echo "$fp" > "$FP"; exit 0; }

echo "$(date '+%F %T') new wallpaper: $src"
# Home Manager applies the working tree: never apply (and commit) half-finished edits of other files.
if ! git -C "$REPO" diff --quiet HEAD -- home-manager ':!home-manager/palette.nix'; then
  echo "$(date '+%F %T') uncommitted changes in home-manager/: theme NOT applied"
  osascript -e 'display notification "Uncommitted changes in home-manager/: theme not applied (run scripts/theme-sync.sh after committing)" with title "Theme"'
  exit 0
fi
"$REPO/scripts/theme-sync.sh" || { echo "theme-sync failed"; osascript -e 'display notification "Theme update failed (see ~/Library/Logs/macos-config/theme-auto.log)" with title "Theme"'; exit 1; }
echo "$sum" > "$REPO/wallpapers/source.sha256"; echo "$fp" > "$FP"
"$REPO/scripts/capture.sh" >/dev/null
# Accept only the theme files; anything else stays pending for review.
"$REPO/scripts/capture.sh" --accept tools/neru/config/config.toml tools/omniwm/config/settings.toml 2>/dev/null
# Commit exactly these paths (git commit -- <paths>): anything else the user staged stays staged.
paths=(home-manager/palette.nix home-manager/palettes tools/neru/config/config.toml tools/omniwm/config/settings.toml)
cd "$REPO" && git add -- "${paths[@]}" \
  && git commit -qm "auto: theme from the current wallpaper" -- "${paths[@]}" && echo "commit $(git log --format=%h -1)"
scheme="$(sed -n 's/.*scheme = "\(.*\)"; author.*/\1/p' "$REPO/home-manager/palette.nix")"
osascript -e "display notification \"Palette $scheme applied\" with title \"Theme follows the wallpaper\""
