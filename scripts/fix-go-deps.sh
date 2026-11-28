#!/usr/bin/env bash
# Regenerate an image's dependency patch with the given Go module bumps:
#   scripts/fix-go-deps.sh images/<name> <module@version>...
#
# Starts from upstream's pristine source at the pinned commit, bumps exactly
# the named modules (plus any the image already bumped, at the higher version),
# and writes patches/0001-bump-vulnerable-go-modules.patch. The patch touches
# go.mod and go.sum only (ADR-003 §6). Prints the bumps, one per line, as
# "module old -> new".
#
# `go get` runs in the image's own pinned toolchain image and needs the network.
# No `go mod tidy`: it rewrites more than the fix needs.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

DIR=${1:?usage: fix-go-deps.sh images/<name> <module@version>...}
shift
[ $# -gt 0 ] || {
  echo "fix-go-deps: no modules to bump" >&2
  exit 1
}
DIR=$(cd "${DIR%/}" && pwd)
PATCH="$DIR/patches/0001-bump-vulnerable-go-modules.patch"
go_tag=$(sed -n 's/^ARG GO_TAG=//p' "$DIR/Containerfile" | head -n1)
[ -n "$go_tag" ] || {
  echo "fix-go-deps: $DIR/Containerfile has no ARG GO_TAG" >&2
  exit 1
}

# Wanted versions: the ones asked for now, and the ones already bumped. For a
# module in both, the higher version wins.
previous=$("$ROOT/scripts/yaml-to-json.sh" "$DIR/image.yaml" |
  jq -r '(.deviations // [])[] | (.bumps // [])[] | capture("^(?<m>\\S+) \\S+ -> (?<v>\\S+)$") | "\(.m)@\(.v)"' 2>/dev/null || true)
# shellcheck disable=SC2086 # previous is a list of words
targets=$(printf '%s\n' "$@" $previous | grep . | jq -rR '
  capture("^(?<m>.+)@(?<v>.+)$")' | jq -rs '
  def parts: ltrimstr("v") | split("-")[0] | split(".") | map(tonumber? // 0);
  group_by(.m)[] | max_by(.v | parts) | "\(.m)@\(.v)"')

work=$(mktemp -d)
trap 'rm -rf "$work" 2>/dev/null || true' EXIT
SKIP_PATCHES=1 "$ROOT/scripts/fetch-source.sh" "$DIR" "$work/src" >&2

# shellcheck disable=SC2086 # targets is a list of arguments
log=$("$ENGINE" run --rm -v "$work/src:/src" -w /src -e GOFLAGS=-mod=mod -e GOTOOLCHAIN=local \
  "docker.io/library/golang:$go_tag" \
  sh -c 'git config --global --add safe.directory /src && go get "$@" 2>&1 && go mod verify >&2' sh $targets) || {
  printf '%s\n' "$log" >&2
  echo "fix-go-deps: go get failed" >&2
  exit 1
}

mkdir -p "$DIR/patches"
git -C "$work/src" diff -- go.mod go.sum >"$PATCH"
[ -s "$PATCH" ] || {
  echo "fix-go-deps: the bumps changed nothing; is upstream already at these versions?" >&2
  exit 1
}
# An image that drops upstream's vendor/ (build.dropVendor, ADR-003 §7) has
# those files deleted by fetch-source.sh, not by go get. They are not part of
# the patch and are not a change this script made.
drop_vendor=$("$ROOT/scripts/yaml-to-json.sh" "$DIR/image.yaml" | jq -r '.build.dropVendor // false')
ignore='^ M (go\.mod|go\.sum)$'
[ "$drop_vendor" != "true" ] || ignore='^ M (go\.mod|go\.sum)$|^ D vendor/'
others=$(git -C "$work/src" status --porcelain | grep -vE "$ignore" || true)
[ -z "$others" ] || {
  echo "fix-go-deps: go get changed files other than go.mod and go.sum:" >&2
  printf '%s\n' "$others" >&2
  exit 1
}

# Report only the modules that were asked for, not what they pulled along.
for t in $targets; do
  m=${t%@*}
  printf '%s\n' "$log" | sed -n "s|^go: upgraded $m \\(.*\\) => \\(.*\\)$|$m \\1 -> \\2|p"
done
