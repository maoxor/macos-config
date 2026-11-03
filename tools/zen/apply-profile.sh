#!/bin/bash
# Zen Browser: copy user.js into the default profile and place the add-ons (uBlock Origin, Auto Tab Discard) signed
# by addons.mozilla.org. Zen must be closed. Run once after install, and after each change to user.js.
# Rollback: delete user.js from the profile (its values stay until changed in about:config) and remove the add-ons
# in Zen's Add-ons page.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$HOME/Library/Application Support/zen"
if pgrep -xq zen; then echo "Quit Zen first." >&2; exit 1; fi
if [[ ! -f "$root/profiles.ini" ]]; then
  # First run without a window: Zen creates its profile and exits.
  /Applications/Zen.app/Contents/MacOS/zen --headless --screenshot "$(mktemp -d)/first.png" about:blank >/dev/null 2>&1 || true
fi
rel="$(awk -F= '/^\[Install/{i=1;next} /^\[/{i=0} i&&$1=="Default"{print $2; exit}' "$root/profiles.ini")"
profile="$root/$rel"
[[ -n "$rel" && -d "$profile" ]] || { echo "No default Zen profile in $root/profiles.ini" >&2; exit 1; }
cp "$here/user.js" "$profile/user.js"
mkdir -p "$profile/extensions"
add() { # AMO slug, add-on id
  local dest="$profile/extensions/$2.xpi"
  [[ -f "$dest" ]] && return
  curl -fsSL -o "$dest.part" "https://addons.mozilla.org/firefox/downloads/latest/$1/latest.xpi"
  mv "$dest.part" "$dest"
}
add ublock-origin "uBlock0@raymondhill.net"
add auto-tab-discard "{c2c003ee-bd69-42a2-b0e9-6f34222cb046}"
echo "Zen profile ready: $profile"
