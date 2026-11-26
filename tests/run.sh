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
trap '[ -n "${KEEP_TMP:-}" ] || rm -rf "$TMP"' EXIT

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

# ------------------------------------------------------------- tool pins
# One place for every tool image, so Renovate can keep them current and a bump
# is one line. A digest anywhere else is a pin nobody maintains.
stray_pins() {
  ! grep -nE '@sha256:[a-f0-9]{64}' Makefile scripts/*.sh .github/workflows/*.yaml
}
expect_pass "tool pins: no image digest outside tools.env" stray_pins
tools_env_shape() {
  awk '
    /^#/ { comment = $0; next }
    /^$/ { comment = ""; next }
    {
      if ($0 !~ /^[A-Z_]+_IMAGE=[^[:space:]@]+:[^[:space:]@]+@sha256:[a-f0-9]+$/) { print "not NAME_IMAGE=repo:tag@sha256:digest: " $0; bad = 1 }
      if (comment !~ /^# renovate: datasource=docker depName=[^[:space:]]+$/) { print "no renovate comment above: " $0; bad = 1 }
      comment = ""
    }
    END { exit bad }
  ' tools.env
}
expect_pass "tool pins: every tools.env entry is tag@digest with a renovate comment" tools_env_shape

# -------------------------------------------------------------- secrets
# One Partner Connect API key for every component (ADR-002 rule 5). A
# per-image variant would have to be created and rotated for each image.
no_per_image_pyxis_token() {
  ! grep -rnE 'RH_PYXIS_TOKEN_|RH_PYXIS_TOKEN[^ `]*(SUFFIX|\{0\})' \
    .github/workflows scripts images README.md CLAUDE.md docs/setup.md
}
expect_pass "secrets: the Pyxis API key is one shared secret, never per image" no_per_image_pyxis_token

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
base-arg-missing|Containerfile|/^ARG BASE_IMAGE=/d|9
base-unpinned|Containerfile|s/^ARG BASE_TAG=latest@sha256:.*/ARG BASE_TAG=latest/|10
toolchain-unpinned|Containerfile|s/^ARG GO_TAG=1.27.3@sha256:.*/ARG GO_TAG=1.27.3/|10
from-literal-unpinned|Containerfile|s#^FROM docker.io/library/golang:.* AS build#FROM docker.io/library/golang:1.27.3 AS build#|10
test-command-missing|image.yaml|/^  command:/d|11
test-command-empty|image.yaml|s/^  command: .*/  command: []/|11
smoke-port-not-a-number|image.yaml|s/^  port: 8080/  port: http/|14
smoke-port-out-of-range|image.yaml|s/^  port: 8080/  port: 70000/|14
smoke-path-relative|image.yaml|s#^  path: /healthz#  path: healthz#|14
smoke-missing|image.yaml|/^smoke:/,/^  args:/d|14
CASES

dir=$(mutate from-stage-alias Containerfile 's#^COPY --from=build /out /out#COPY --from=build /out /out#')
printf 'FROM build AS again\nFROM scratch\nCOPY --from=again /out /out\n' >>"$dir/Containerfile"
expect_pass "check-image: FROM <earlier stage> and FROM scratch need no digest" scripts/check-image.sh "$dir"

# rule 2 also restricts the name: it ends up in image references, secret names
# and a CI matrix, so it must be a plain lowercase slug.
bad="$TMP/badname/Bad_Name"
mkdir -p "$bad" && cp "$FIX/image-good/Containerfile" "$bad/" &&
  sed -e 's/^name: image-good/name: Bad_Name/' "$FIX/image-good/image.yaml" >"$bad/image.yaml"
expect_fail "check-image: a name that is not a lowercase slug fails rule 2" "rule 2:.*lowercase" scripts/check-image.sh "$bad"

# rule 12: patches and image.yaml deviations must list each other
dir=$(mutate patch-unlisted image.yaml 's/^consumers: \[\]/consumers: []/')
mkdir -p "$dir/patches" && : >"$dir/patches/0001-x.patch"
expect_fail "check-image: a patch not listed in deviations fails rule 12" "rule 12:.*0001-x.patch" scripts/check-image.sh "$dir"
dir=$(mutate patch-listed image.yaml 's/^consumers: \[\]/consumers: []/')
mkdir -p "$dir/patches" && : >"$dir/patches/0001-x.patch"
printf 'deviations:\n  - patch: patches/0001-x.patch\n    reason: fixes a HIGH vulnerability upstream has not fixed\n    fixes: [CVE-0000-00001]\n    upstreamPR: none yet\n' >>"$dir/image.yaml"
expect_pass "check-image: a listed patch with reason and fixes passes" scripts/check-image.sh "$dir"
dir=$(mutate patch-missing image.yaml 's/^consumers: \[\]/consumers: []/')
printf 'deviations:\n  - patch: patches/0009-gone.patch\n    reason: x\n    fixes: [CVE-0000-00001]\n' >>"$dir/image.yaml"
expect_fail "check-image: a deviation whose patch file is missing fails rule 12" "rule 12:.*0009-gone.patch" scripts/check-image.sh "$dir"
dir=$(mutate patch-no-fixes image.yaml 's/^consumers: \[\]/consumers: []/')
mkdir -p "$dir/patches" && : >"$dir/patches/0001-x.patch"
printf 'deviations:\n  - patch: patches/0001-x.patch\n    reason: because\n' >>"$dir/image.yaml"
expect_fail "check-image: a deviation that names no vulnerability fails rule 12" "rule 12:.*fixes" scripts/check-image.sh "$dir"

expect_fail "check-image: missing directory fails" "" scripts/check-image.sh "$TMP/does-not-exist"

# ----------------------------------------------------------- new-image.sh
# Runs in a copy of the repo with a stub git, so it never touches the network.
SANDBOX="$TMP/sandbox"
mkdir -p "$SANDBOX/scripts" "$SANDBOX/images" "$SANDBOX/bin"
cp scripts/new-image.sh scripts/check-image.sh scripts/lib.sh "$SANDBOX/scripts/"
cp tools.env "$SANDBOX/"
# No existing image is copied in: the scaffold must come from the template,
# not from whichever image happens to exist.
cp -R scripts/templates "$SANDBOX/scripts/"
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
expect_pass "new-image: no template placeholder is left behind" \
  bash -c "! grep -rn '__[A-Z]*__' '$SANDBOX/images/annotated'"
expect_pass "new-image: the scaffolded Containerfile passes hadolint" \
  make -s lint-containerfiles CONTAINERFILES="tests/.tmp/sandbox/images/annotated/Containerfile"
expect_pass "new-image: scaffolds a lightweight tag" new_image light example/light v2.0.0
expect_pass "new-image: lightweight tag pins the tag's own commit" \
  has images/light/image.yaml "commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
expect_fail "new-image: refuses an existing directory" "exists" new_image annotated example/annotated v1.0.0
expect_fail "new-image: fails on an unknown tag" "not found" new_image ghost example/ghost v9.9.9
expect_fail "new-image: missing arguments fail" "" new_image only-a-name
expect_fail "new-image: refuses a name that is not a lowercase slug" "lowercase" new_image Bad_Name example/annotated v1.0.0

# The scaffold is deliberately incomplete: the licence is TODO, the start-up
# test command is empty and the smoke test has no port. check-image must flag
# exactly those three.
scaffold_out=$(cd "$SANDBOX" && scripts/check-image.sh images/annotated 2>&1)
scaffold_rules=$(printf '%s\n' "$scaffold_out" | grep -Eo ': rule [0-9]+:' | sort -u | tr -d ':\n')
if [ "$scaffold_rules" = " rule 11 rule 14 rule 4" ]; then
  ok "new-image: scaffold fails only rule 4 (licence), 11 (test command) and 14 (smoke test)"
else
  ko "new-image: scaffold fails only rules 4, 11 and 14" "got: '$scaffold_rules'
$scaffold_out"
fi

# -------------------------------------------------------- fetch-source.sh
# A throwaway local repository plays the upstream, so no network is needed.
UP="$TMP/upstream"
mkdir -p "$UP"
(
  cd "$UP" || exit 1
  git init -q -b main .
  git config user.email test@example.com
  git config user.name test
  git config uploadpack.allowAnySHA1InWant true
  printf 'module example.com/up\n\ngo 1.27\n' >go.mod
  printf 'package main\n\nfunc main() {}\n' >main.go
  git add . && git commit -q -m one
  git tag -a v1.0.0 -m v1.0.0
  printf '// two\n' >>main.go
  git commit -q -am two
  git tag v1.1.0
) >/dev/null 2>&1
SHA1=$(git -C "$UP" rev-parse 'v1.0.0^{commit}')
SHA2=$(git -C "$UP" rev-parse 'v1.1.0^{commit}')

# fs_image <case> <version> <commit>: an image dir whose upstream is $UP
fs_image() {
  local dir="$TMP/fs/$1/img"
  mkdir -p "$dir"
  cat >"$dir/image.yaml" <<YAML
kind: container
name: img
upstream:
  repo: file://$UP
  version: $2
  commit: $3
YAML
  echo "$dir"
}
src_has() { grep -q -- "$2" "$1"; }

d=$(fs_image ok-annotated v1.0.0 "$SHA1")
expect_pass "fetch-source: annotated tag at the pinned commit" scripts/fetch-source.sh "$d" "$TMP/fs/ok-annotated/src"
expect_pass "fetch-source: checked-out tree is the pinned commit, not the branch tip" \
  bash -c "! grep -q two '$TMP/fs/ok-annotated/src/main.go'"
# Hermeto refuses a source directory that is not a git repository, so .git
# stays until prefetch.sh has run.
expect_pass "fetch-source: .git is kept for the prefetch" \
  bash -c "[ -d '$TMP/fs/ok-annotated/src/.git' ]"
d=$(fs_image ok-light v1.1.0 "$SHA2")
expect_pass "fetch-source: lightweight tag at the pinned commit" scripts/fetch-source.sh "$d" "$TMP/fs/ok-light/src"
d=$(fs_image moved v1.0.0 "$SHA2")
expect_fail "fetch-source: tag pointing at another commit fails" "tag v1.0.0 .* not .*$SHA2" \
  scripts/fetch-source.sh "$d" "$TMP/fs/moved/src"
d=$(fs_image no-tag v9.9.9 "$SHA1")
expect_fail "fetch-source: unknown tag fails" "tag v9.9.9 not found" scripts/fetch-source.sh "$d" "$TMP/fs/no-tag/src"
d=$(fs_image no-commit v1.0.0 ffffffffffffffffffffffffffffffffffffffff)
expect_fail "fetch-source: unknown commit fails" "" scripts/fetch-source.sh "$d" "$TMP/fs/no-commit/src"
d=$(fs_image exists v1.0.0 "$SHA1")
mkdir -p "$TMP/fs/exists/src" && touch "$TMP/fs/exists/src/x"
expect_fail "fetch-source: refuses a non-empty output directory" "not empty" scripts/fetch-source.sh "$d" "$TMP/fs/exists/src"

# make_patch <file> <line to append>: a patch against the v1.0.0 tree
make_patch() {
  local w="$TMP/fs/patchwork"
  rm -rf "$w" && git clone -q "$UP" "$w" 2>/dev/null && git -C "$w" checkout -q "$SHA1" 2>/dev/null
  printf '%s\n' "$2" >>"$w/$1"
  git -C "$w" diff
}
d=$(fs_image patch-dep v1.0.0 "$SHA1")
mkdir -p "$d/patches" && make_patch go.mod 'require example.com/dep v1.2.3' >"$d/patches/0001-bump-dep.patch"
expect_pass "fetch-source: a dependency-only patch applies" scripts/fetch-source.sh "$d" "$TMP/fs/patch-dep/src"
expect_pass "fetch-source: the patch changed go.mod" src_has "$TMP/fs/patch-dep/src/go.mod" "example.com/dep v1.2.3"
d=$(fs_image patch-code v1.0.0 "$SHA1")
mkdir -p "$d/patches" && make_patch main.go '// patched' >"$d/patches/0001-code.patch"
expect_fail "fetch-source: a patch touching source code fails" "main.go.*ADR-003" \
  scripts/fetch-source.sh "$d" "$TMP/fs/patch-code/src"
d=$(fs_image patch-stale v1.0.0 "$SHA1")
mkdir -p "$d/patches" && make_patch go.mod 'x' | sed 's/go 1.27/go 9.99/' >"$d/patches/0001-stale.patch"
expect_fail "fetch-source: a patch that does not apply fails" "" scripts/fetch-source.sh "$d" "$TMP/fs/patch-stale/src"

# ------------------------------------------------------------ check-vex.sh
# NOW pins "today" to 2026-12-01T00:00:00Z so the expiry cases do not rot.
VEX_NOW=1796083200

# vex_image <case> <statements-json>: the good fixture plus a VEX file
vex_image() {
  local dir="$TMP/vex/$1/image-good"
  mkdir -p "$dir"
  cp "$FIX/image-good/image.yaml" "$dir/"
  [ -z "$2" ] || cat >"$dir/vex.openvex.json" <<JSON
{
  "@context": "https://openvex.dev/ns/v0.2.0",
  "@id": "https://github.com/stakater/certified-images/images/image-good/vex",
  "author": "tests",
  "timestamp": "2026-11-25T00:00:00Z",
  "version": 1,
  "statements": [$2]
}
JSON
  echo "$dir"
}
NA='"vulnerability":{"name":"CVE-0000-00001"},"status":"not_affected","justification":"vulnerable_code_not_in_execute_path","impact_statement":"not reachable","x-stakater-owner":"a@stakater.com"'
UI='"vulnerability":{"name":"CVE-0000-00002"},"status":"under_investigation","x-stakater-owner":"a@stakater.com"'
THIS='"products":[{"@id":"pkg:oci/image-good?tag=v1.2.3-1"}]'
OTHER='"products":[{"@id":"pkg:oci/image-good?tag=v1.2.2-4"}]'

expect_pass "check-vex: no VEX file passes" \
  env NOW=$VEX_NOW scripts/check-vex.sh "$(vex_image none '')"
# Built in variables first: bash 3.2 (macOS) brace-expands "{a,b}" when it is
# quoted inside a command substitution.
stmt_na="{$NA,$THIS}"
stmt_ui="{$UI,$THIS,\"x-stakater-expires\":\"2026-12-20T00:00:00Z\"}"
expect_pass "check-vex: not_affected for the current upstream version passes" \
  env NOW=$VEX_NOW scripts/check-vex.sh "$(vex_image na-ok "$stmt_na")"
expect_pass "check-vex: under_investigation with a future expiry passes" \
  env NOW=$VEX_NOW scripts/check-vex.sh "$(vex_image ui-ok "$stmt_ui")"

while IFS='|' read -r name stmt pattern; do
  [ -z "$name" ] && continue
  expect_fail "check-vex: $name fails" "$pattern" \
    env NOW=$VEX_NOW scripts/check-vex.sh "$(vex_image "$name" "$stmt")"
done <<CASES
not_affected for another upstream version|{$NA,$OTHER}|CVE-0000-00001.*v1.2.3
not_affected without a justification|{"vulnerability":{"name":"CVE-0000-00001"},"status":"not_affected","x-stakater-owner":"a@stakater.com",$THIS}|justification
statement without an owner|{"vulnerability":{"name":"CVE-0000-00001"},"status":"not_affected","justification":"x","impact_statement":"y",$THIS}|owner
under_investigation without an expiry|{$UI,$THIS}|CVE-0000-00002.*expires
under_investigation past its expiry|{$UI,$THIS,"x-stakater-expires":"2026-11-30T00:00:00Z"}|CVE-0000-00002.*expired
expiry more than 30 days after the document timestamp|{$UI,$THIS,"x-stakater-expires":"2027-02-01T00:00:00Z"}|30 days
accepted-risk affected statement without an expiry|{"vulnerability":{"name":"CVE-0000-00003"},"status":"affected","action_statement":"accepted","x-stakater-owner":"a@stakater.com",$THIS}|CVE-0000-00003.*expires
unknown status|{"vulnerability":{"name":"CVE-0000-00004"},"status":"ignored","x-stakater-owner":"a@stakater.com",$THIS}|status
CASES

d=$(vex_image broken-json '')
echo '{ not json' >"$d/vex.openvex.json"
expect_fail "check-vex: a file that is not JSON fails" "" env NOW=$VEX_NOW scripts/check-vex.sh "$d"
expect_pass "check-vex: the documented example is valid in shape" \
  bash -c "d=\$(mktemp -d '$TMP/vexex.XXXX')/EXAMPLE && mkdir -p \$d && sed -e 's/^name: image-good/name: EXAMPLE/' '$FIX/image-good/image.yaml' >\$d/image.yaml && cp docs/vex-example.openvex.json \$d/vex.openvex.json && NOW=$VEX_NOW scripts/check-vex.sh \$d"

# ---------------------------------------------------------- next-release.sh
# next_release <version> <expected> <tags...>
next_release() {
  local version=$1 expected=$2 got
  shift 2
  got=$(printf '%s\n' "$@" | scripts/next-release.sh "$version") || return 1
  [ "$got" = "$expected" ] || {
    echo "expected $expected, got $got"
    return 1
  }
}
expect_pass "next-release: no tags gives 1" next_release v1.2.3 1 ""
expect_pass "next-release: after -1 and -2 comes 3" next_release v1.2.3 3 v1.2.3-1 v1.2.3-2
expect_pass "next-release: numeric, not alphabetic (10 after 9)" next_release v1.2.3 11 v1.2.3-9 v1.2.3-10
expect_pass "next-release: other versions are ignored" next_release v1.2.3 2 v1.2.2-7 v1.2.3-1 v1.2.4-5
expect_pass "next-release: a longer version with the same prefix is ignored" next_release v1.2 1 v1.2.3-4 v1.20-9
expect_pass "next-release: signature and non-numeric tags are ignored" \
  next_release v1.2.3 2 v1.2.3-1 v1.2.3 latest v1.2.3-rc1 sha256-abc.sig v1.2.3-1.att
expect_fail "next-release: a version is required" "" bash -c 'echo | scripts/next-release.sh'

# ------------------------------------------------------------ list-tags.sh
# A stub engine stands in for crane. STUB_OUT is what it prints, STUB_RC its
# exit status. Getting this wrong reuses a release number, so only an explicit
# "this repository does not exist" may count as "no tags".
STUB_ENGINE="$TMP/stub-engine"
cat >"$STUB_ENGINE" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$STUB_OUT"
exit "${STUB_RC:-0}"
STUB
chmod +x "$STUB_ENGINE"
# list_tags <rc> <engine output>: runs list-tags.sh against the stub
list_tags() {
  STUB_RC=$1 STUB_OUT=$2 ENGINE="$STUB_ENGINE" REGISTRY_AUTH_FILE=/nonexistent \
    scripts/list-tags.sh registry.example/repo
}
tags_are() { # <expected lines, space separated> <rc> <engine output>
  local got
  got=$(list_tags "$2" "$3" 2>/dev/null | tr '\n' ' ') || return 1
  [ "$got" = "$1" ] || {
    echo "expected '$1', got '$got'"
    return 1
  }
}
expect_pass "list-tags: prints the tags the registry returns" \
  tags_are "v1.2.3-1 v1.2.3-2 " 0 "v1.2.3-1
v1.2.3-2"
expect_pass "list-tags: an existing repository with no tags is empty" tags_are "" 0 ""
expect_pass "list-tags: a repository the registry does not know is empty" \
  tags_are "" 1 'Error: reading tags for registry.example/repo: GET https://registry.example/v2/repo/tags/list: NAME_UNKNOWN: repository name not known to registry'
while IFS='|' read -r name out; do
  [ -z "$name" ] && continue
  expect_fail "list-tags: $name is an error, not 'no tags'" "could not list tags" list_tags 1 "$out"
done <<'CASES'
connection refused|level=fatal msg="pinging container registry: dial tcp 10.0.0.1:5000: connect: connection refused"
DNS failure|level=fatal msg="dial tcp: lookup registry.example: no such host"
unauthorized|level=fatal msg="fetching tags list: unauthorized: access to the requested resource is not authorized"
a tool image that could not be pulled|docker: Error response from daemon: manifest for gcr.io/x@sha256:abc not found: manifest unknown: manifest unknown
a timeout|level=fatal msg="fetching tags list: context deadline exceeded"
an empty error|
CASES
expect_fail "list-tags: success with output that is not a list of tags is an error" "could not list tags" \
  list_tags 0 'Error: something went wrong'

tag_free() { # <tag> <engine output>
  STUB_RC=0 STUB_OUT=$2 ENGINE="$STUB_ENGINE" REGISTRY_AUTH_FILE=/nonexistent \
    scripts/assert-tag-free.sh registry.example/repo "$1"
}
expect_pass "assert-tag-free: a tag that does not exist is free" tag_free v1.2.3-2 'v1.2.3-1'
expect_fail "assert-tag-free: an existing tag is refused" "already exists" tag_free v1.2.3-1 'v1.2.3-1'
expect_pass "assert-tag-free: a tag that only shares a prefix is free" tag_free v1.2.3-1 'v1.2.3-10'
expect_fail "assert-tag-free: if the tags cannot be listed, it refuses" "could not list tags" \
  env STUB_RC=1 STUB_OUT="connection refused" ENGINE="$STUB_ENGINE" REGISTRY_AUTH_FILE=/nonexistent \
  scripts/assert-tag-free.sh registry.example/repo v1.2.3-1

# ---------------------------------------------------------- publish-plan.sh
# plan_image <case> <componentId>
plan_image() {
  local dir="$TMP/plan/$1/image-good"
  mkdir -p "$dir"
  sed -e "s/componentId: .*/componentId: \"$2\"/" "$FIX/image-good/image.yaml" >"$dir/image.yaml"
  echo "$dir"
}
plan_has() { # capture first: see hook_runs for why not to pipe into grep -q
  local out
  out=$(scripts/publish-plan.sh "$1") || return 1
  printf '%s\n' "$out" | grep -qx -- "$2"
}
d=$(plan_image placeholder TODO-PARTNER-CONNECT-COMPONENT-ID)
expect_pass "publish-plan: a placeholder component ID is not publishable" plan_has "$d" "publishable=false"
expect_pass "publish-plan: and it says why" bash -c "out=\$(scripts/publish-plan.sh '$d') && printf '%s\n' \"\$out\" | grep -q '^reason=.*componentId'"
d=$(plan_image real 0123456789abcdef01234567)
expect_pass "publish-plan: a real component ID is publishable" plan_has "$d" "publishable=true"
expect_pass "publish-plan: repository is Red Hat's partner registry path" \
  plan_has "$d" "repository=quay.io/redhat-isv-containers/0123456789abcdef01234567"
expect_pass "publish-plan: version comes from image.yaml" plan_has "$d" "version=v1.2.3"
expect_pass "publish-plan: suffix comes from image.yaml" plan_has "$d" "suffix=IMAGE_GOOD"
d=$(plan_image malformed not-an-id)
expect_fail "publish-plan: a malformed component ID fails" "componentId" scripts/publish-plan.sh "$d"

# staging registry (ADR-002 rev 5): every image, component ID or not
d=$(plan_image placeholder TODO-PARTNER-CONNECT-COMPONENT-ID)
expect_pass "publish-plan: an image without a component ID still has a staging repository" \
  plan_has "$d" "staging_repository=ghcr.io/stakater/ubi/image-good"
d=$(plan_image real 0123456789abcdef01234567)
expect_pass "publish-plan: an image with a component ID has the same staging repository" \
  plan_has "$d" "staging_repository=ghcr.io/stakater/ubi/image-good"
# An image in staging has passed our checks, not Red Hat's.
staging_not_called_certified() {
  local out
  out=$(scripts/publish-plan.sh "$d") || return 1
  ! printf '%s\n' "$out" | grep '^staging_repository=' | grep -qi certified
}
expect_pass "publish-plan: the staging path does not say 'certified'" staging_not_called_certified

# ------------------------------------------------------ assert-not-public.sh
# Staging packages must not be anonymously pullable (ADR-002 rev 5). A stub
# curl stands in for the registry: STUB_TOKEN_BODY is the token endpoint's
# answer, STUB_CODE the HTTP status of the anonymous tags request.
STUB_BIN="$TMP/stub-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"/token?"*) printf '%s' "$STUB_TOKEN_BODY" ;;
  *) printf '%s' "$STUB_CODE" ;;
esac
exit "${STUB_CURL_RC:-0}"
STUB
chmod +x "$STUB_BIN/curl"
not_public() { # <token body> <http code> [curl rc]
  STUB_TOKEN_BODY=$1 STUB_CODE=$2 STUB_CURL_RC=${3:-0} PATH="$STUB_BIN:$PATH" \
    scripts/assert-not-public.sh ghcr.io/stakater/ubi/example
}
expect_pass "assert-not-public: anonymous access refused (401) passes" not_public '{"token":"t"}' 401
expect_pass "assert-not-public: anonymous access denied (403) passes" not_public '{"token":"t"}' 403
expect_pass "assert-not-public: a registry that gives no anonymous token passes" not_public '{"errors":[{"code":"DENIED"}]}' 401
expect_pass "assert-not-public: a package that does not exist yet (404) passes" not_public '{"token":"t"}' 404
expect_fail "assert-not-public: anonymous access allowed (200) fails" "PUBLIC" not_public '{"token":"t"}' 200
expect_fail "assert-not-public: an unexpected status fails, it is not assumed private" "could not tell" not_public '{"token":"t"}' 500
expect_fail "assert-not-public: a network failure fails, it is not assumed private" "could not tell" not_public '' 000 7
expect_fail "assert-not-public: a repository outside ghcr.io is refused" "ghcr.io" \
  env PATH="$STUB_BIN:$PATH" scripts/assert-not-public.sh quay.io/x/y

# ------------------------------------------------------------ copy-image.sh
# The stub prints STUB_OUT for every call; copy-image reads the destination
# digest from it after the copy. D1/D2 are two different digests.
D1=sha256:1111111111111111111111111111111111111111111111111111111111111111
D2=sha256:2222222222222222222222222222222222222222222222222222222222222222
copy_image() { # <rc> <engine output> <src-ref>
  STUB_RC=$1 STUB_OUT=$2 ENGINE="$STUB_ENGINE" REGISTRY_AUTH_FILE=/nonexistent \
    scripts/copy-image.sh "$3" dst.example/repo v1.2.3-1
}
copy_prints() {
  local out
  out=$(copy_image "$@" 2>/dev/null) || return 1
  [ "$out" = "dst.example/repo@$D1" ] || {
    echo "got '$out'"
    return 1
  }
}
expect_pass "copy-image: an unchanged digest prints the destination reference" \
  copy_prints 0 "$D1" "src.example/repo@$D1"
expect_fail "copy-image: a digest that changed in transit fails" "digest" copy_image 0 "$D2" "src.example/repo@$D1"
expect_fail "copy-image: a failed copy fails" "" copy_image 1 "connection refused" "src.example/repo@$D1"
expect_fail "copy-image: a source without a digest is refused" "digest" copy_image 0 "$D1" "src.example/repo:v1.2.3-1"

dir=$(mutate component-id-malformed image.yaml 's/componentId: .*/componentId: "not-an-id"/')
expect_fail "check-image: a malformed component ID fails rule 13" "rule 13:" scripts/check-image.sh "$dir"
dir=$(mutate component-id-real image.yaml 's/componentId: .*/componentId: "0123456789abcdef01234567"/')
expect_pass "check-image: a 24-hex component ID passes" scripts/check-image.sh "$dir"

# -------------------------------------------------------- changed-images.sh
CH="$TMP/changed"
mkdir -p "$CH/scripts" "$CH/images/a" "$CH/images/b" "$CH/docs"
cp scripts/changed-images.sh "$CH/scripts/" 2>/dev/null
(
  cd "$CH" || exit 1
  git init -q -b main .
  git config user.email test@example.com
  git config user.name test
  echo a >images/a/image.yaml && echo b >images/b/image.yaml && echo d >docs/x.md
  git add . && git commit -q -m base
  echo a2 >images/a/Containerfile && git add . && git commit -q -m "change a"
  echo d2 >docs/x.md && git add . && git commit -q -m "docs only"
  git rm -q -r images/b && git commit -q -m "remove b"
  mkdir -p images/c && echo c >images/c/image.yaml && echo x >images/a/image.yaml
  git add . && git commit -q -m "add c, change a"
) >/dev/null 2>&1
rev() { git -C "$CH" rev-parse "$1"; }
changed() { # <before> <after> <expected-json>
  local got
  got=$(cd "$CH" && scripts/changed-images.sh "$1" "$2") || return 1
  [ "$got" = "$3" ] || {
    echo "expected $3, got $got"
    return 1
  }
}
expect_pass "changed-images: a change inside one image lists that image" \
  changed "$(rev HEAD~4)" "$(rev HEAD~3)" '["images/a"]'
expect_pass "changed-images: a docs-only change lists nothing" \
  changed "$(rev HEAD~3)" "$(rev HEAD~2)" '[]'
expect_pass "changed-images: a deleted image is not listed" \
  changed "$(rev HEAD~2)" "$(rev HEAD~1)" '[]'
expect_pass "changed-images: several changed images are listed, sorted" \
  changed "$(rev HEAD~1)" "$(rev HEAD)" '["images/a","images/c"]'
expect_pass "changed-images: an all-zero before lists every image" \
  changed 0000000000000000000000000000000000000000 "$(rev HEAD)" '["images/a","images/c"]'

# ------------------------------------------------------------ smoke-test.sh
# The pod the smoke test runs, rendered without a cluster. Each line is a
# setting OpenShift's restricted security context imposes or that we add.
RENDERED=$(scripts/smoke-test.sh --render registry.example/img@sha256:abc "$FIX/image-good" 2>&1) || RENDERED="RENDER FAILED: $RENDERED"
rendered_has() { printf '%s\n' "$RENDERED" | grep -qE -- "$1"; }
while IFS='|' read -r name pattern; do
  [ -z "$name" ] && continue
  expect_pass "smoke-test: the pod $name" rendered_has "$pattern"
done <<'CASES'
runs the image under test|image: "?registry.example/img@sha256:abc
must run as non-root|runAsNonRoot: true
runs as an arbitrary high UID|runAsUser: 1000680000
runs in group 0, as on OpenShift|runAsGroup: 0
uses the default seccomp profile|type: RuntimeDefault
forbids privilege escalation|allowPrivilegeEscalation: false
drops every capability|^ +- ALL$
has a read-only root filesystem|readOnlyRootFilesystem: true
does not mount an API token by default|automountServiceAccountToken: false
probes the declared port|port: 8080
probes the declared path|path: "?/healthz
passes the declared environment|name: "?LOG_LEVEL
passes the declared arguments|^ +- serve$
never restarts on its own, so a crash is visible|restartPolicy: Never
CASES
rendered_omits_uid() {
  local out
  out=$(SMOKE_RUN_AS_USER="" scripts/smoke-test.sh --render registry.example/img@sha256:abc "$FIX/image-good") || return 1
  ! printf '%s\n' "$out" | grep -q 'runAsUser'
}
expect_pass "smoke-test: on OpenShift the UID is left for the cluster to assign" rendered_omits_uid

# ------------------------------------------------------------ verify hook
hook() { printf '%s' "$1" | VERIFY_CMD="echo VERIFY-RAN" scripts/verify-hook.sh 2>&1; }
# Capture first, then match the command's own output line. Piping straight into
# `grep -q` let grep exit on the hook's announcement line and kill the hook
# with SIGPIPE, which failed the pipeline at random.
hook_runs() {
  local out
  out=$(hook "{\"tool_input\":{\"file_path\":\"$ROOT/$1\"}}") || return 1
  printf '%s\n' "$out" | grep -qx 'VERIFY-RAN'
}
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
