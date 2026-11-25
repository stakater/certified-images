#!/usr/bin/env bash
# Check one image directory against the rules no standard linter knows:
#   scripts/check-image.sh images/<name>
# Reports every broken rule as "rule N: ..." and exits 1 if any is broken.
# The rules and their reasons are in docs/planning/dx2-make-verify.md.
set -euo pipefail

ENGINE=${ENGINE:-docker}
YQ_IMAGE=${YQ_IMAGE:-docker.io/mikefarah/yq:4.54.3@sha256:7834187596ad56fd5a81436114e0b0b9dd54c91bb43946d1f7145b2be5f9c3d2}

DIR=${1:?usage: check-image.sh images/<name>}
DIR=${DIR%/}
YAML="$DIR/image.yaml"
CF="$DIR/Containerfile"

for f in "$YAML" "$CF"; do
  [ -f "$f" ] || {
    echo "$DIR: missing $f" >&2
    exit 1
  }
done

# A check that cannot run must fail, never pass by default.
JSON=$("$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$YAML") || {
  echo "$DIR: could not read $YAML as YAML (is $ENGINE running?)" >&2
  exit 1
}

errors=0
err() {
  errors=$((errors + 1))
  echo "$DIR: rule $1: $2" >&2
}
get() { printf '%s' "$JSON" | jq -r "$1 // \"\""; }

# rule 1: kind (ADR-005)
kind=$(get .kind)
case "$kind" in
  container | xpkg) ;;
  *) err 1 "kind must be 'container' or 'xpkg', got '$kind'" ;;
esac

# rule 2: name equals the directory name
name=$(get .name)
[ "$name" = "$(basename "$DIR")" ] || err 2 "name '$name' must equal the directory name '$(basename "$DIR")'"

# rule 3: pinned upstream (ADR-003 §1)
repo=$(get .upstream.repo)
version=$(get .upstream.version)
commit=$(get .upstream.commit)
[[ "$repo" =~ ^https://[^[:space:]]+$ ]] || err 3 "upstream.repo must be an https:// URL, got '$repo'"
[ -n "$version" ] || err 3 "upstream.version must be set"
[[ "$commit" =~ ^[a-f0-9]{40}$ ]] || err 3 "upstream.commit must be 40 hex characters, got '$commit'"

# rule 4: licence recorded (ADR-002 rule 1b)
license=$(get .upstream.license)
if [ -z "$license" ] || [ "$license" = "TODO" ]; then
  err 4 "upstream.license must be set (ADR-002 rule 1), got '$license'"
fi

# rule 5: the shape Renovate's regex manager matches (renovate.json):
#   # renovate: datasource=... depName=...
#   version: ...
#   commit: ...
if ! awk '
  /^[[:space:]]*# renovate: datasource=[^[:space:]]+ depName=[^[:space:]]+[[:space:]]*$/ { c = NR; next }
  c && NR == c + 1 && /^[[:space:]]*version: [^[:space:]]+/ { v = NR; next }
  v && NR == v + 1 && /^[[:space:]]*commit: [a-f0-9]+/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$YAML"; then
  err 5 "'# renovate: datasource=… depName=…' must sit directly above 'version:', with 'commit:' on the next line"
fi

# rule 6: typed fetchers only (ADR-003 §4)
prefetch=$(get .build.prefetch)
if [ -z "$prefetch" ]; then
  err 6 "build.prefetch must be set"
elif ! printf '%s' "$prefetch" | jq -e 'type == "object" or type == "array"' >/dev/null 2>&1; then
  err 6 "build.prefetch must be a JSON object or array, got '$prefetch'"
elif printf '%s' "$prefetch" | jq -e '[.. | objects | select(.type == "generic")] | length > 0' >/dev/null; then
  err 6 "build.prefetch uses the 'generic' fetcher; typed fetchers only (ADR-003 §4)"
fi

# rule 7: secret suffix is usable in a GitHub secret name
suffix=$(get .redhat.secretSuffix)
[[ "$suffix" =~ ^[A-Z0-9_]+$ ]] || err 7 "redhat.secretSuffix must match [A-Z0-9_]+, got '$suffix'"

# rule 8: no drift between image.yaml and the Containerfile ARG defaults.
# Renovate bumps image.yaml only; a stale ARG means wrong labels or toolchain.
drift() { # <ARG name> <expected value> <image.yaml field>
  local values
  values=$(sed -n "s/^ARG $1=//p" "$CF" | sort -u)
  if [ -z "$values" ]; then
    err 8 "Containerfile has no 'ARG $1=' default; expected '$2' ($3)"
  elif [ "$values" != "$2" ]; then
    err 8 "Containerfile ARG $1 is '$(echo "$values" | tr '\n' ' ' | sed 's/ $//')' but $3 is '$2'"
  fi
}
drift UPSTREAM_VERSION "$version" upstream.version
drift UPSTREAM_COMMIT "$commit" upstream.commit
go_version=$(get .build.goVersion)
[ -z "$go_version" ] || drift GO_VERSION "$go_version" build.goVersion

# rule 9: parameterised base (ADR-004)
for arg in BASE_REGISTRY BASE_IMAGE BASE_TAG; do
  grep -q "^ARG $arg=" "$CF" || err 9 "Containerfile must declare 'ARG $arg=' (ADR-004)"
done

[ "$errors" -eq 0 ] || exit 1
echo "$DIR: ok"
