#!/usr/bin/env bash
# Check one image directory against the rules no standard linter knows:
#   scripts/check-image.sh images/<name>
# Reports every broken rule as "rule N: ..." and exits 1 if any is broken.
# The rules and their reasons are in docs/planning/dx2-make-verify.md.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

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
[[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || err 2 "name '$name' must be a lowercase slug: letters, digits and hyphens"
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

# rule 7 is retired: it checked the field that named per-image secrets. No
# secret is named per image any more (ADR-002 rev 7).

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

# rule 9: parameterised base (ADR-004)
for arg in BASE_REGISTRY BASE_IMAGE BASE_TAG; do
  grep -q "^ARG $arg=" "$CF" || err 9 "Containerfile must declare 'ARG $arg=' (ADR-004)"
done

# rule 10: every external image is pinned by digest (ADR-004). An unpinned
# base or toolchain is an unpinned build input.
while IFS= read -r line; do
  [[ "$line" =~ ^ARG[[:space:]]+([A-Z0-9_]*_TAG)=(.*)$ ]] || continue
  arg=${BASH_REMATCH[1]}
  value=${BASH_REMATCH[2]}
  [[ "$value" =~ ^[^@[:space:]]+@sha256:[a-f0-9]{64}$ ]] ||
    err 10 "ARG $arg must be tag@sha256:<digest>, got '$value' (ADR-004)"
done <"$CF"
stages=" scratch "
while read -r _ ref as alias _; do
  case "$ref" in --platform=*) err 10 "FROM $ref: put the platform on the build command, not in the Containerfile" ;; esac
  if [[ "$stages" != *" $ref "* ]] && [[ "$ref" != *'_TAG}'* ]] && [[ "$ref" != *@sha256:* ]]; then
    err 10 "FROM $ref is not pinned: use an ARG ending in _TAG that holds tag@sha256:<digest>, or a literal digest (ADR-004)"
  fi
  [ "$(printf '%s' "${as:-}" | tr '[:lower:]' '[:upper:]')" = "AS" ] && stages="$stages$alias "
done < <(grep -E '^FROM[[:space:]]' "$CF")

# rule 11: a start-up test command, so a published image is known to run
if ! printf '%s' "$JSON" | jq -e '(.test.command // []) | type == "array" and length > 0 and all(.[]; type == "string" and . != "" and . != "TODO")' >/dev/null; then
  err 11 "test.command must be a non-empty list of arguments that make the image exit 0 (e.g. [\"--help\"])"
fi

# rule 12: every patch is a recorded deviation, and every recorded deviation
# has its patch (ADR-002 rule 2). A deviation exists only to fix a
# vulnerability, so it must name what it fixes.
listed=$(printf '%s' "$JSON" | jq -r '(.deviations // [])[] | .patch // ""')
shopt -s nullglob
for patch in "$DIR"/patches/*.patch; do
  rel="patches/$(basename "$patch")"
  printf '%s\n' "$listed" | grep -qxF "$rel" || err 12 "$rel is not listed under deviations in image.yaml (ADR-002 rule 2)"
done
shopt -u nullglob
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  [ -f "$DIR/$rel" ] || err 12 "deviation lists $rel, but that file does not exist"
done <<<"$listed"
bad=$(printf '%s' "$JSON" | jq -r '(.deviations // [])[] | select(((.reason // "") == "") or (((.fixes // []) | length) == 0)) | .patch // "(no patch)"')
[ -z "$bad" ] || err 12 "deviation $(echo "$bad" | tr '\n' ' ')needs a reason and a non-empty fixes list of vulnerability IDs"

# rule 13: the Partner Connect component ID is the placeholder or a real ID.
# A typo here would push to the wrong repository.
component=$(get .redhat.componentId)
case "$component" in
  TODO*) ;;
  *) [[ "$component" =~ ^[a-f0-9]{24}$ ]] || err 13 "redhat.componentId must be the TODO placeholder or 24 hex characters, got '$component'" ;;
esac

# rule 14: a smoke test, so the image is run as a pod and asked to serve
# (scripts/smoke-test.sh). Starting with --help proves very little.
smoke_port=$(get .smoke.port)
smoke_path=$(get .smoke.path)
if ! [[ "$smoke_port" =~ ^[0-9]+$ ]] || [ "$smoke_port" -lt 1 ] || [ "$smoke_port" -gt 65535 ]; then
  err 14 "smoke.port must be the port the image serves HTTP on (1-65535), got '$smoke_port'"
fi
[[ "$smoke_path" == /* ]] || err 14 "smoke.path must be an HTTP path that answers 2xx when the image is healthy (starting with /), got '$smoke_path'"

# rule 15: the label policy (ADR-009). The Containerfile must set every label
# the policy lists, or the image inherits the base's; and image.yaml must give
# the catalog tags. scripts/check-labels.sh checks the values on the built image.
if ! printf '%s' "$JSON" | jq -e '(.tags // []) | type == "array" and length > 0 and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9-]*$"))' >/dev/null; then
  err 15 "tags must be a non-empty list of lowercase slugs; they become io.openshift.tags (ADR-009)"
fi
for label in name vendor maintainer version release summary description \
  io.k8s.display-name io.k8s.description io.openshift.tags \
  org.opencontainers.image.title org.opencontainers.image.description org.opencontainers.image.vendor \
  org.opencontainers.image.version org.opencontainers.image.licenses org.opencontainers.image.source \
  org.opencontainers.image.revision org.opencontainers.image.created org.opencontainers.image.url \
  org.opencontainers.image.base.name org.opencontainers.image.base.digest \
  vcs-ref vcs-type build-date url \
  com.stakater.upstream.repo com.stakater.upstream.version com.stakater.upstream.commit; do
  grep -Eq "^(LABEL)?[[:space:]]+${label//./\\.}=" "$CF" || err 15 "Containerfile does not set the label '$label' (ADR-009)"
done

# rule 16: staging visibility is public or private; absent means private
# (ADR-002 rev 6). Declaring public is a decision, made in a reviewed PR.
visibility=$(get .staging.visibility)
case "$visibility" in
  "" | public | private) ;;
  *) err 16 "staging.visibility must be 'public' or 'private' (default private), got '$visibility'" ;;
esac

[ "$errors" -eq 0 ] || exit 1
echo "$DIR: ok"
