#!/usr/bin/env bash
# Fetch an image's upstream source at its pinned commit (ADR-003 §1, §6):
#   scripts/fetch-source.sh images/<name> <output-dir>
#
# 1. Fetches upstream.commit, and only that commit.
# 2. Fails unless the tag upstream.version points at that commit. A tag that
#    was moved or re-pointed after we pinned it stops the build.
# 3. Applies images/<name>/patches/*.patch, which may touch dependency
#    manifests and lockfiles only.
# .git is left in place: Hermeto refuses a source directory that is not a git
# repository. scripts/prefetch.sh removes it once the prefetch is done.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

DIR=${1:?usage: fetch-source.sh images/<name> <output-dir>}
OUT=${2:?usage: fetch-source.sh images/<name> <output-dir>}
DIR=${DIR%/}
YAML="$DIR/image.yaml"

die() {
  echo "fetch-source: $*" >&2
  exit 1
}

[ -f "$YAML" ] || die "missing $YAML"
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
  die "output directory $OUT is not empty"
fi

JSON=$("$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$YAML") || die "could not read $YAML (is $ENGINE running?)"
get() { printf '%s' "$JSON" | jq -r "$1 // \"\""; }
REPO=$(get .upstream.repo)
VERSION=$(get .upstream.version)
COMMIT=$(get .upstream.commit)
[ -n "$REPO" ] && [ -n "$VERSION" ] && [ -n "$COMMIT" ] || die "$YAML must set upstream.repo, upstream.version and upstream.commit"

# The tag must point at the pinned commit. Annotated tags are dereferenced
# (the ^{} line); lightweight tags point at the commit directly.
refs=$(git ls-remote "$REPO" "refs/tags/$VERSION" "refs/tags/$VERSION^{}") || die "could not list tags of $REPO"
tag_commit=$(printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ { print $1 }')
[ -n "$tag_commit" ] || tag_commit=$(printf '%s\n' "$refs" | awk 'NF { print $1 }' | head -n1)
[ -n "$tag_commit" ] || die "tag $VERSION not found in $REPO"
[ "$tag_commit" = "$COMMIT" ] ||
  die "tag $VERSION points at $tag_commit, not the pinned commit $COMMIT. The tag moved, or image.yaml is wrong. Do not build."

mkdir -p "$OUT"
git -C "$OUT" init -q
git -C "$OUT" remote add origin "$REPO"
git -C "$OUT" fetch -q --depth 1 origin "$COMMIT" || die "could not fetch commit $COMMIT from $REPO"
git -C "$OUT" -c advice.detachedHead=false checkout -q FETCH_HEAD
head=$(git -C "$OUT" rev-parse HEAD)
[ "$head" = "$COMMIT" ] || die "checked out $head, expected $COMMIT"

# Patches: dependency manifests and lockfiles only (ADR-003 §6).
allowed() {
  case "$(basename "$1")" in
    go.mod | go.sum | go.work | go.work.sum | requirements*.txt | package.json | package-lock.json) return 0 ;;
    *) return 1 ;;
  esac
}
# SKIP_PATCHES=1 gives upstream's pristine source: scripts/fix-go-deps.sh
# regenerates the dependency patch from it.
shopt -s nullglob
patches=("$DIR"/patches/*.patch)
[ -z "${SKIP_PATCHES:-}" ] || patches=()
for patch in ${patches[@]+"${patches[@]}"}; do
  files=$(git -C "$OUT" apply --numstat "$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")" | cut -f3) ||
    die "patch $patch does not apply to $VERSION"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    allowed "$f" || die "patch $patch touches $f. Patches may change dependency manifests and lockfiles only (ADR-003 §6)."
  done <<<"$files"
  git -C "$OUT" apply "$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")" || die "patch $patch does not apply to $VERSION"
  echo "fetch-source: applied $(basename "$patch")" >&2
done

echo "fetch-source: $REPO $VERSION @ $COMMIT -> $OUT" >&2
