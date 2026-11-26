#!/usr/bin/env bash
# Test a built image before anything else looks at it:
#   scripts/test-image.sh <image-ref> images/<name>
#
# Checks what Red Hat certification and OpenShift need, and that the image
# actually starts: labels match image.yaml, /licenses is populated, the user is
# not root, the architecture is amd64, and the container exits 0 for
# image.yaml's test.command, both as its own user and as an arbitrary UID in
# group 0 (how OpenShift runs it). The container gets no network.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REF=${1:?usage: test-image.sh <image-ref> images/<name>}
DIR=${2:?usage: test-image.sh <image-ref> images/<name>}
DIR=${DIR%/}

JSON=$("$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$DIR/image.yaml") || {
  echo "test-image: could not read $DIR/image.yaml" >&2
  exit 1
}
INSPECT=$("$ENGINE" image inspect "$REF") || {
  echo "test-image: image $REF not found locally" >&2
  exit 1
}
get() { printf '%s' "$JSON" | jq -r "$1 // \"\""; }
cfg() { printf '%s' "$INSPECT" | jq -r ".[0] | $1 // \"\""; }

failures=0
check() { # <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    failures=$((failures + 1))
    echo "FAIL - $1: expected '$3', got '$2'"
  fi
}
present() { # <description> <value>
  if [ -n "$2" ]; then
    echo "ok   - $1"
  else
    failures=$((failures + 1))
    echo "FAIL - $1: empty"
  fi
}


# Labels (ADR-009): Red Hat's required ones, what built the image, what is
# inside it and what it is based on. Checked against image.yaml, this checkout's
# commit and the base digest pinned in the Containerfile.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
printf '%s' "$INSPECT" | jq '.[0].Config.Labels // {}' >"$tmp/labels.json"
printf '%s' "$JSON" >"$tmp/image.json"
vcs=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)
if [ -n "$vcs" ] && [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then vcs="$vcs-dirty"; fi
base=$(sed -n 's/^ARG BASE_TAG=.*@\(sha256:[a-f0-9]*\)$/\1/p' "$DIR/Containerfile")
if EXPECT_RELEASE="${RELEASE:-}" EXPECT_VCS_REF="$vcs" EXPECT_BASE_DIGEST="$base" \
  "$ROOT/scripts/check-labels.sh" "$tmp/labels.json" "$tmp/image.json"; then
  :
else
  failures=$((failures + 1))
fi
rm -rf "$tmp"

check "architecture" "$(cfg .Architecture)" "amd64"

user=$(cfg .Config.User)
case "$user" in
  "" | 0 | root | 0:* | root:*)
    failures=$((failures + 1))
    echo "FAIL - runs as non-root: USER is '${user:-unset}'"
    ;;
  *) echo "ok   - runs as non-root (USER $user)" ;;
esac

# /licenses must hold at least one file (preflight HasLicense). Read from the
# filesystem export, so it works on images with no shell.
cid=$("$ENGINE" create --platform linux/amd64 "$REF")
licenses=$("$ENGINE" export "$cid" | tar -t 2>/dev/null | grep -E '^licenses/.+[^/]$' || true)
"$ENGINE" rm -f "$cid" >/dev/null
present "/licenses holds files" "$licenses"

# It starts. No network: a start-up check must not depend on the internet.
cmd=()
while IFS= read -r arg; do cmd+=("$arg"); done < <(printf '%s' "$JSON" | jq -r '.test.command[]')
start() { # <description> <extra run args...>
  local desc=$1 out
  shift
  if out=$("$ENGINE" run --rm --network=none --platform linux/amd64 "$@" "$REF" "${cmd[@]}" 2>&1); then
    echo "ok   - $desc"
  else
    failures=$((failures + 1))
    echo "FAIL - $desc: '${cmd[*]}' exited non-zero"
    printf '%s\n' "$out" | tail -n 20 | sed 's/^/       /'
  fi
}
start "starts as its own user (${cmd[*]})"
start "starts as an arbitrary UID in group 0, as on OpenShift" --user 1234567:0

echo
if [ "$failures" -eq 0 ]; then
  echo "test-image: $REF passed"
else
  echo "test-image: $REF failed $failures check(s)"
  exit 1
fi
