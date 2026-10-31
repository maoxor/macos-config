#!/bin/bash
# Offline repo checks: no machine state read, runs anywhere (also in GitHub Actions).
#   scripts/check.sh    exit 1 if any check fails
# Complements verify.sh (machine vs repo drift); run both before committing.
set -u
REPO="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 2
rc=0
fail() { echo "  FAIL  $*"; rc=1; }
files() { git ls-files "$@"; }

echo "== Syntax"
while read -r f; do bash -n "$f" 2>/dev/null || fail "bash -n $f"; done < <(files '*.sh')
while read -r f; do python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null || fail "python $f"; done < <(files '*.py')
luac=$(command -v luac luac5.4 luac5.3 2>/dev/null | head -1)
if [ -n "$luac" ]; then while read -r f; do "$luac" -p "$f" 2>/dev/null || fail "lua $f"; done < <(files '*.lua')
else echo "  skip  lua (luac not installed)"; fi

echo "== ShellCheck"
if command -v shellcheck >/dev/null; then sc=(shellcheck)
elif command -v nix >/dev/null; then sc=(nix run nixpkgs#shellcheck --)
else sc=(); echo "  skip  (shellcheck not installed)"; fi
if [ "${#sc[@]}" -gt 0 ]; then
  sh=(); while read -r f; do sh+=("$f"); done < <(files '*.sh')  # bash 3.2: no mapfile
  "${sc[@]}" -S warning "${sh[@]}" 2>/dev/null || fail "shellcheck (run: shellcheck -S warning <file>)"
fi

echo "== Tracked configs (tools/configs.tsv)"
awk -F'\t' 'NR==1{n=NF} NF!=n{printf "  FAIL  tools/configs.tsv:%d has %d columns, header has %d\n", NR, NF, n; bad=1} END{exit bad}' tools/configs.tsv || rc=1
while IFS=$'\t' read -r id type dest; do
  case "$type" in file|plist) [ -e "$dest" ] || fail "configs.tsv $id: $dest missing";; esac
done < <(awk -F'\t' 'NR>1{print $1"\t"$2"\t"$4}' tools/configs.tsv)

echo "== Regression tests"
# capture.sh --accept must refuse dirty target paths, including paths with spaces (fixed 2026-10-09).
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/repo/scripts" "$t/home"
cp scripts/lib.sh scripts/capture.sh "$t/repo/scripts/"
(cd "$t/repo" && git init -q && mkdir "a b" && echo old > "a b/c.txt" && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm init && echo dirty > "a b/c.txt")
st="$t/home/.local/state/macos-power-user-deploy/capture-pending"; mkdir -p "$st"
echo new > "$st/f"; printf '%s\t%s\n' "$st/f" "a b/c.txt" > "$st/MANIFEST"
out=$(HOME="$t/home" "$t/repo/scripts/capture.sh" --accept 2>&1); code=$?
if [ "$code" = 1 ] && grep -q dirty "$t/repo/a b/c.txt"; then echo "  ok    capture --accept refuses a dirty path with spaces"
else fail "capture --accept overwrote a dirty path (exit $code): $out"; fi

# theme-auto must commit only the theme paths and skip when other home-manager files are edited
# (it used to commit whatever was staged, 2026-10-10).
r="$t/theme"; mkdir -p "$r/home-manager" && (cd "$r" && git init -q && echo a > home-manager/palette.nix \
  && echo a > home-manager/startup.nix && echo a > other.txt && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm init)
(cd "$r" && echo b > home-manager/palette.nix && echo b > other.txt && git add other.txt \
  && git -c user.name=t -c user.email=t@t commit -qm theme -- home-manager/palette.nix)
still_staged=$(git -C "$r" diff --cached --name-only)
committed=$(git -C "$r" show --name-only --format= HEAD)
if [ "$still_staged" = other.txt ] && [ "$committed" = home-manager/palette.nix ] \
   && git -C "$r" diff --quiet HEAD -- home-manager ':!home-manager/palette.nix' \
   && (echo b > "$r/home-manager/startup.nix"; ! git -C "$r" diff --quiet HEAD -- home-manager ':!home-manager/palette.nix') \
   && grep -q 'git commit -qm .* -- "${paths\[@\]}"' scripts/theme-auto.sh \
   && grep -q "diff --quiet HEAD -- home-manager ':!home-manager/palette.nix'" scripts/theme-auto.sh
then echo "  ok    theme-auto commits only theme paths and skips unrelated home-manager edits"
else fail "theme-auto commit isolation / home-manager guard"; fi

# The OmniWM registry must agree with the captured settings.toml: theme-sync runs apply-registry.py,
# and a stale registry silently reverted the user's gestures and layouts (2026-10-15).
cp tools/omniwm/config/settings.toml "$t/omniwm.toml"
reg=$(OMNIWM_SCREEN=2074x1340 python3 -I tools/omniwm/apply-registry.py "$t/omniwm.toml" | tail -1)
if [ "$reg" = "0 change(s)" ]; then echo "  ok    OmniWM registry matches tools/omniwm/config/settings.toml"
else fail "apply-registry.py would change the captured settings.toml ($reg): update the registry or the capture"; fi

# jobgate's decisions (admission, PyTorch watermarks, pause choice, USL fit) on fixed inputs.
if out=$(python3 -I scripts/jobgate.py self-test 2>&1); then echo "  ok    jobgate decisions ($(echo "$out" | grep -c '^  ok') cases)"
else fail "jobgate self-test:"; echo "$out" | grep FAIL | sed 's/^/        /'; fi

# The Swift tools are rebuilt at login by swift-tool.sh: a file that no longer compiles would take its agent down,
# the memory guard included. macOS only (no Swift toolchain on the Linux CI).
if [ "$(uname)" = Darwin ]; then
  for src in scripts/*.swift; do
    if out=$(/usr/bin/swiftc -typecheck "$src" 2>&1); then echo "  ok    $src compiles"
    else fail "$src does not compile:"; echo "$out" | grep -m3 error | sed 's/^/        /'; fi
  done
fi

# Portability: no code file may hardcode a user home or the original clone location (install.sh
# writes identity.nix; scripts find the repo from their own path; Lua reads ~/.config/macos-config/repo).
hard=$(files '*.sh' '*.lua' '*.py' '*.nix' | grep -vE '/identity.nix$|^scripts/check.sh$' \
  | xargs grep -nE '/Users/[a-z]|dev/macos-config|src/omniwm"' 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*(#|--)|portable-default' || true)
if [ -z "$hard" ]; then echo "  ok    no hardcoded user paths in code"
else fail "hardcoded user paths:"; echo "$hard" | sed 's/^/        /'; fi

[ "$rc" = 0 ] && echo "All checks passed."
exit "$rc"
