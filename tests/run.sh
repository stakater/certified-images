#!/usr/bin/env bash
# Tests for the factory's own checks and scripts (story DX.2).
# Plain bash, no framework. Run from anywhere: tests/run.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
FIX="tests/fixtures"
TMP="$ROOT/tests/.tmp"
rm -rf "$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  echo "ok   - $1"
}
ko() {
  fail=$((fail + 1))
  echo "FAIL - $1"
  [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'
}

# expect_pass <name> <cmd...>: the command must exit 0
expect_pass() {
  local name=$1 out
  shift
  if out=$("$@" 2>&1); then ok "$name"; else ko "$name" "$out"; fi
}

# expect_fail <name> <pattern> <cmd...>: the command must exit non-zero and
# its output must match <pattern> (extended regex; "" skips the match)
expect_fail() {
  local name=$1 pattern=$2 out
  shift 2
  if out=$("$@" 2>&1); then
    ko "$name" "expected failure, but it passed"
  elif [ -n "$pattern" ] && ! printf '%s' "$out" | grep -Eq -- "$pattern"; then
    ko "$name" "failed, but output did not match /$pattern/:
$out"
  else
    ok "$name"
  fi
}

# ---------------------------------------------------------------- linters
# Each linter target must reject its broken fixture. A linter that cannot fail
# is not a check.
expect_fail "hadolint rejects a bad Containerfile" "DL[0-9]+" \
  make -s lint-containerfiles CONTAINERFILES="$FIX/bad/Containerfile"
expect_fail "shellcheck rejects a bad script" "SC[0-9]+" \
  make -s lint-shell SHELL_SCRIPTS="$FIX/bad/bad.sh"
expect_fail "actionlint rejects a bad workflow" "bad.yaml" \
  make -s lint-workflows WORKFLOWS="$FIX/bad/workflows/bad.yaml"
expect_fail "renovate validator rejects a bad config" "" \
  make -s check-renovate RENOVATE_CONFIG="$FIX/bad/renovate.json"

# --------------------------------------------------------- check-image.sh
expect_pass "check-image: good fixture passes" scripts/check-image.sh "$FIX/image-good"

# mutate <case-name> <file> <sed-expression>: copy the good fixture and break it
mutate() {
  local dir="$TMP/$1/image-good"
  mkdir -p "$dir"
  cp "$FIX/image-good/image.yaml" "$FIX/image-good/Containerfile" "$dir/"
  sed -i.bak -e "$3" "$dir/$2" && rm -f "$dir/$2.bak"
  echo "$dir"
}

# name | file | sed expression | rule the error must name
while IFS='|' read -r name file expr rule; do
  [ -z "$name" ] && continue
  dir=$(mutate "$name" "$file" "$expr")
  expect_fail "check-image: $name fails rule $rule" "rule $rule:" scripts/check-image.sh "$dir"
done <<'CASES'
kind-bundle|image.yaml|s/^kind: container/kind: bundle/|1
name-mismatch|image.yaml|s/^name: image-good/name: other/|2
repo-not-https|image.yaml|s#repo: https://#repo: git://#|3
version-empty|image.yaml|s/version: v1.2.3/version: ""/|3
commit-short|image.yaml|s/commit: 0123456789abcdef0123456789abcdef01234567/commit: 0123456/|3
license-todo|image.yaml|s/license: Apache-2.0/license: TODO/|4
renovate-comment-missing|image.yaml|/# renovate:/d|5
prefetch-not-json|image.yaml|s/prefetch: .*/prefetch: 'not json'/|6
prefetch-generic|image.yaml|s/"type": "gomod"/"type": "generic"/|6
secret-suffix-lowercase|image.yaml|s/secretSuffix: IMAGE_GOOD/secretSuffix: image-good/|7
version-drift|Containerfile|s/^ARG UPSTREAM_VERSION=v1.2.3/ARG UPSTREAM_VERSION=v1.2.2/|8
commit-drift|Containerfile|s/^ARG UPSTREAM_COMMIT=0123/ARG UPSTREAM_COMMIT=ffff/|8
go-version-drift|Containerfile|s/^ARG GO_VERSION=1.27.3/ARG GO_VERSION=1.26.0/|8
base-arg-missing|Containerfile|/^ARG BASE_IMAGE=/d|9
CASES

expect_fail "check-image: missing directory fails" "" scripts/check-image.sh "$TMP/does-not-exist"

# ----------------------------------------------------------- new-image.sh
# Runs in a copy of the repo with a stub git, so it never touches the network.
SANDBOX="$TMP/sandbox"
mkdir -p "$SANDBOX/scripts" "$SANDBOX/images" "$SANDBOX/bin"
cp scripts/new-image.sh scripts/check-image.sh "$SANDBOX/scripts/"
cp -R images/opencost "$SANDBOX/images/"
cat >"$SANDBOX/bin/git" <<'STUB'
#!/usr/bin/env bash
# Stub for `git ls-remote <url> <ref>`.
#   v1.0.0 is an annotated tag: the ^{} ref gives the commit.
#   v2.0.0 is a lightweight tag: only the plain ref exists.
[ "$1" = "ls-remote" ] || exit 1
case "$3" in
  'refs/tags/v1.0.0^{}') printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t%s\n' "$3" ;;
  'refs/tags/v1.0.0') printf '1111111111111111111111111111111111111111\t%s\n' "$3" ;;
  'refs/tags/v2.0.0') printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t%s\n' "$3" ;;
esac
exit 0
STUB
chmod +x "$SANDBOX/bin/git"
new_image() { (cd "$SANDBOX" && PATH="$SANDBOX/bin:$PATH" scripts/new-image.sh "$@"); }
has() { grep -q -- "$2" "$SANDBOX/$1"; }

expect_pass "new-image: scaffolds an annotated tag" new_image annotated example/annotated v1.0.0
expect_pass "new-image: annotated tag pins the dereferenced commit" \
  has images/annotated/image.yaml "commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expect_pass "new-image: Containerfile carries the same commit" \
  has images/annotated/Containerfile "^ARG UPSTREAM_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
expect_pass "new-image: scaffolds a lightweight tag" new_image light example/light v2.0.0
expect_pass "new-image: lightweight tag pins the tag's own commit" \
  has images/light/image.yaml "commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
expect_fail "new-image: refuses an existing directory" "exists" new_image annotated example/annotated v1.0.0
expect_fail "new-image: fails on an unknown tag" "not found" new_image ghost example/ghost v9.9.9
expect_fail "new-image: missing arguments fail" "" new_image only-a-name

# The scaffold is deliberately incomplete: licence and Go version are TODO.
# check-image must flag exactly those two and nothing else.
scaffold_out=$(cd "$SANDBOX" && scripts/check-image.sh images/annotated 2>&1)
scaffold_rules=$(printf '%s\n' "$scaffold_out" | grep -Eo ': rule [0-9]+:' | sort -u | tr -d ':\n')
if [ "$scaffold_rules" = " rule 4 rule 8" ]; then
  ok "new-image: scaffold fails only rule 4 (licence TODO) and rule 8 (Go version TODO)"
else
  ko "new-image: scaffold fails only rule 4 and rule 8" "got: '$scaffold_rules'
$scaffold_out"
fi

# ------------------------------------------------------------ verify hook
hook() { printf '%s' "$1" | VERIFY_CMD="echo VERIFY-RAN" scripts/verify-hook.sh 2>&1; }
hook_runs() { hook "{\"tool_input\":{\"file_path\":\"$ROOT/$1\"}}" | grep -q VERIFY-RAN; }
hook_skips() { ! hook_runs "$1"; }

for f in images/opencost/Containerfile images/opencost/image.yaml scripts/new-image.sh \
  renovate.json Makefile .github/workflows/verify.yaml tests/run.sh .hadolint.yaml; do
  expect_pass "hook: runs verify after editing $f" hook_runs "$f"
done
for f in docs/roadmap.md README.md CLAUDE.md; do
  expect_pass "hook: does nothing after editing $f" hook_skips "$f"
done
expect_fail "hook: a failing verify fails the hook" "" \
  bash -c "printf '%s' '{\"file_path\":\"$ROOT/Makefile\"}' | VERIFY_CMD=false scripts/verify-hook.sh"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
