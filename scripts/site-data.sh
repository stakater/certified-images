#!/usr/bin/env bash
# The catalogue site's data (story S.1, ADR-002 rev 12):
#   scripts/site-data.sh <out-dir>
#
# Writes <out-dir>/catalog.json: every image declared public, with what the
# site shows about it. Nothing on the site is typed in by hand except
# site/external.json; everything else is read here, at generation time, from:
#   - images/<name>/ (image.yaml, Containerfile, the tests) and stacks/
#   - the registry: its releases and their digests (scripts/list-tags.sh, crane)
#   - GitHub: whether each release's build provenance verifies
#     (gh attestation verify), and the daily re-scan's open issue, if any
#   - Red Hat's public catalogue: whether the image is listed there
#   - the newest release itself: its container configuration and size (crane),
#     its signature and its signed SBOMs (cosign), and a scan of it for
#     vulnerabilities of every severity (trivy), all with the pinned tools
#
# Also writes <out-dir>/details/<name>.json (configuration, SBOM packages, scan
# findings) and <out-dir>/sbom/<name>.<kind>.spdx.json (the signed SBOMs, for
# download).
#
# An image that is not declared public (staging.visibility) is left out.
# Where a source cannot be read the value is "unknown". It is never the
# favourable answer: nothing is "verified" or "listed" unless it was seen.
#
# SITE_OFFLINE=1 skips the registry, GitHub and Red Hat (the unit tests).
# SITE_IMAGES_DIR, SITE_STACKS_DIR, SITE_EXTERNAL point at other inputs.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

OUT=${1:?usage: site-data.sh <out-dir>}
IMAGES=${SITE_IMAGES_DIR:-$ROOT/images}
STACKS=${SITE_STACKS_DIR:-$ROOT/stacks}
EXTERNAL=${SITE_EXTERNAL:-$ROOT/site/external.json}
PREFIX=${SITE_REGISTRY_PREFIX:-ghcr.io/stakater/ubi}
REPO=${SITE_REPO:-stakater/certified-images}
SIGNER="$REPO/.github/workflows/build-certify.yaml"
PLACEHOLDER=TODO-PARTNER-CONNECT-COMPONENT-ID
MAX_RELEASES=${SITE_MAX_RELEASES:-12}
# Who must have signed: this repository's pipeline, on main.
SIGNER_RE="^https://github.com/$REPO/\\.github/workflows/build-certify\\.yaml@refs/heads/main\$"
ISSUER=https://token.actions.githubusercontent.com
TRIVY_CACHE=${SITE_TRIVY_CACHE:-$ROOT/.ctx/.site-trivy-cache}
offline=false
[ -z "${SITE_OFFLINE:-}" ] || offline=true

die() {
  echo "site-data: $*" >&2
  exit 1
}
[ -d "$IMAGES" ] || die "no image directory at $IMAGES"
[ -f "$EXTERNAL" ] || die "missing $EXTERNAL"
jq -e 'type == "array"' "$EXTERNAL" >/dev/null || die "$EXTERNAL must be a JSON array"
mkdir -p "$OUT/details" "$OUT/sbom"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

have_gh=false
if [ "$offline" = false ] && command -v gh >/dev/null; then have_gh=true; fi

# stacks_of <image>: the stacks that list it, as a JSON array
stacks_of() {
  local image=$1 sdir names=""
  for sdir in "$STACKS"/*/; do
    [ -f "${sdir}images" ] || continue
    if grep -v '^[[:space:]]*#' "${sdir}images" | tr -d '[:blank:]' | grep -qx -- "$image"; then
      names="$names$(basename "$sdir")"$'\n'
    fi
  done
  printf '%s' "$names" | jq -R . | jq -cs .
}

# functional_text <dir>: what the image's functional test says it proves: the
# comment block at the top of functional/test.sh, without its first paragraph
# (which says where the test is run from, not what it proves). If the block
# has only one paragraph, that one is used.
functional_text() {
  local f="$1/functional/test.sh" block rest
  [ -f "$f" ] || return 0
  block=$(sed -n '2,/^[^#]/p' "$f" | sed -n 's/^# \{0,1\}//p')
  rest=$(printf '%s\n' "$block" | awk 'seen { print } /^[[:space:]]*$/ { seen = 1 }')
  if [ -n "$rest" ]; then printf '%s\n' "$rest"; else printf '%s\n' "$block"; fi
}

# redhat_status <name> <component id>: JSON {status, address?}
redhat_status() {
  local name=$1 id=$2 code body
  if [ -z "$id" ] || [ "$id" = "$PLACEHOLDER" ]; then
    echo '{"status":"not-submitted"}'
    return
  fi
  if [ "$offline" = true ]; then
    echo '{"status":"unknown"}'
    return
  fi
  body="$work/rh.json"
  code=$(curl -s --max-time 30 -o "$body" -w '%{http_code}' \
    "https://catalog.redhat.com/api/containers/v1/repositories/registry/registry.connect.redhat.com/repository/stakater/$name" || true)
  if [ "$code" = "200" ] && jq -e '.published == true' "$body" >/dev/null 2>&1; then
    jq -cn --arg a "registry.connect.redhat.com/stakater/$name" '{status: "listed", address: $a}'
  elif [ "$code" = "404" ] || { [ "$code" = "200" ] && jq -e '.published == false' "$body" >/dev/null 2>&1; }; then
    echo '{"status":"not-listed"}'
  else
    echo '{"status":"unknown"}'
  fi
}

# releases <repository>: JSON array, newest first, of {tag, digest, provenance}
releases() {
  local repo=$1 tags tag digest prov
  if [ "$offline" = true ]; then
    echo '[]'
    return
  fi
  tags=$("$ROOT/scripts/list-tags.sh" "$repo" 2>/dev/null) || die "could not list the tags of $repo"
  : >"$work/releases.jsonl"
  # A release tag is <upstream version>-<release number>. Newest first.
  for tag in $(printf '%s\n' "$tags" | grep -E -- '-[0-9]+$' | grep -v '^sha256-' | sort -Vr | sed -n "1,${MAX_RELEASES}p"); do
    digest=$(crane digest "$repo:$tag" 2>/dev/null | tail -n 1) || digest=""
    [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || die "could not read the digest of $repo:$tag"
    prov=unknown
    if [ "$have_gh" = true ]; then
      if gh attestation verify "oci://$repo@$digest" --repo "$REPO" --signer-workflow "$SIGNER" >/dev/null 2>&1; then
        prov=verified
      else
        prov=none
      fi
    fi
    jq -cn --arg tag "$tag" --arg digest "$digest" --arg prov "$prov" \
      '{tag: $tag, digest: $digest, provenance: $prov}' >>"$work/releases.jsonl"
  done
  jq -cs . "$work/releases.jsonl"
}

# findings <name>: the daily re-scan's open issue for the image, if any
findings() {
  local name=$1 out
  if [ "$have_gh" = false ]; then
    echo '{"status":"unknown"}'
    return
  fi
  if out=$(gh issue list --repo "$REPO" --state open --label vulnerability \
    --search "\"Vulnerabilities in $name\" in:title" --json number,url,updatedAt 2>/dev/null); then
    printf '%s' "$out" | jq -c --arg t "Vulnerabilities in $name" \
      'if length > 0 then {status: "open", url: .[0].url, updated: .[0].updatedAt} else {status: "none"} end'
  else
    echo '{"status":"unknown"}'
  fi
}

cosign() { "$ENGINE" run --rm "$COSIGN_IMAGE" "$@" --certificate-identity-regexp "$SIGNER_RE" --certificate-oidc-issuer "$ISSUER"; }

# details <name> <repository> <digest of the newest release, or empty>
# Writes details/<name>.json and the SBOM files, and prints the scan summary
# for the catalogue. Whatever cannot be read stays "unknown" with no numbers:
# an unread scan must never look like a clean one.
details() {
  local name=$1 repo=$2 digest=$3 ref n total kind tool count files
  local container=null signature=unknown
  local sbom='{"status":"unknown","packages":null,"files":[]}'
  local scan='{"status":"unknown","findings":null}'
  local summary='{"status":"unknown"}'
  if [ "$offline" = false ] && [ -n "$digest" ]; then
    ref="$repo@$digest"

    # The container as the registry describes it.
    if crane config "$ref" >"$work/config.json" 2>/dev/null && crane manifest "$ref" >"$work/manifest.json" 2>/dev/null; then
      container=$(jq -c --slurpfile m "$work/manifest.json" '
        { architecture, os, created, user: .config.User,
          entrypoint: (.config.Entrypoint // []), command: (.config.Cmd // []),
          ports: ((.config.ExposedPorts // {}) | keys), workdir: (.config.WorkingDir // ""),
          layers: ($m[0].layers | length), size: ([$m[0].layers[].size] | add),
          labels: (.config.Labels // {}) }' "$work/config.json" 2>/dev/null) || container=null
    fi

    # The signature.
    if cosign verify "$ref" >/dev/null 2>&1; then signature=verified; else signature=none; fi

    # The signed SBOMs: verified, then unpacked. One comes from syft (what is
    # in the image), one from Hermeto (what the build was given).
    if cosign verify-attestation --type spdxjson "$ref" >"$work/att.jsonl" 2>/dev/null && [ -s "$work/att.jsonl" ]; then
      files='[]'
      n=0
      total=$(grep -c . "$work/att.jsonl")
      while [ "$n" -lt "$total" ]; do
        n=$((n + 1))
        sed -n "${n}p" "$work/att.jsonl" |
          jq -c '.payload | @base64d | fromjson | .predicate | if type == "string" then fromjson else . end' >"$work/spdx.json" 2>/dev/null || continue
        tool=$(jq -r '[.creationInfo.creators[]? | select(startswith("Tool: ")) | ltrimstr("Tool: ")] | first // "unknown"' "$work/spdx.json")
        case "$tool" in syft*) kind=image ;; *) kind=dependencies ;; esac
        count=$(jq '.packages | length' "$work/spdx.json")
        cp "$work/spdx.json" "$OUT/sbom/$name.$kind.spdx.json"
        files=$(printf '%s' "$files" | jq -c --arg kind "$kind" --arg file "sbom/$name.$kind.spdx.json" --arg tool "$tool" --argjson n "$count" \
          'map(select(.kind != $kind)) + [{kind: $kind, file: $file, tool: $tool, packages: $n}]')
      done
      if [ -f "$OUT/sbom/$name.image.spdx.json" ]; then
        sbom=$(jq -c --argjson files "$files" '
          { status: "verified", files: $files,
            packages: ([ .packages[]
              | ([.externalRefs[]? | select(.referenceType == "purl") | .referenceLocator] | first // "") as $purl
              | select($purl != "")
              | { n: .name, v: (.versionInfo // ""),
                  t: ($purl | ltrimstr("pkg:") | split("/")[0]),
                  l: ((.licenseDeclared // .licenseConcluded // "") | if . == "NOASSERTION" then "" else . end) } ]
              | unique_by([.t, .n, .v]) | sort_by([.t, .n])) }' "$OUT/sbom/$name.image.spdx.json")
      else
        sbom=$(jq -cn --argjson files "$files" '{status: "verified", packages: null, files: $files}')
      fi
    else
      sbom='{"status":"none","packages":null,"files":[]}'
    fi

    # A scan of the newest release, every severity, fixable or not. The CVE
    # gate at build time is narrower: fixable critical and high only.
    mkdir -p "$TRIVY_CACHE"
    if "$ENGINE" run --rm -v "$TRIVY_CACHE:/root/.cache/trivy" "$TRIVY_IMAGE" image --platform linux/amd64 \
      --scanners vuln --no-progress --format json "$ref" >"$work/scan.json" 2>/dev/null &&
      jq -e '.SchemaVersion' "$work/scan.json" >/dev/null 2>&1; then
      scan=$(jq -c --arg scanner "trivy $(printf '%s' "${TRIVY_IMAGE%@*}" | sed 's/.*://')" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        def rank: {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3} [.] // 4;
        ([ .Results[]? | .Type as $type | .Vulnerabilities[]?
           | { id: .VulnerabilityID, severity: .Severity, pkg: .PkgName, installed: .InstalledVersion,
               fixed: (.FixedVersion // ""), title: (.Title // ""), kind: $type } ]
         | unique_by([.id, .pkg]) | sort_by([(.severity | rank), .pkg, .id])) as $f
        | { status: "scanned", scanner: $scanner, scannedAt: $at, total: ($f | length),
            bySeverity: ($f | group_by(.severity) | map({(.[0].severity): length}) | add // {}),
            fixableCriticalHigh: ([$f[] | select((.severity == "CRITICAL" or .severity == "HIGH") and .fixed != "")] | length),
            findings: $f }' "$work/scan.json")
      summary=$(printf '%s' "$scan" | jq -c 'del(.findings)')
    fi
  fi
  jq -n --argjson container "$container" --arg signature "$signature" --argjson sbom "$sbom" --argjson scan "$scan" \
    '{container: $container, signature: $signature, sbom: $sbom, scan: $scan}' >"$OUT/details/$name.json"
  printf '%s\n' "$summary"
}

: >"$work/images.jsonl"
for dir in "$IMAGES"/*/; do
  dir=${dir%/}
  [ -f "$dir/image.yaml" ] || continue
  name=$(basename "$dir")
  json=$("$ROOT/scripts/yaml-to-json.sh" "$dir/image.yaml" 2>/dev/null) ||
    die "could not read $dir/image.yaml; fix it, the image is not skipped"
  printf '%s' "$json" | jq -e 'type == "object" and (.name | type == "string")' >/dev/null 2>&1 ||
    die "$dir/image.yaml is not an image manifest; fix it, the image is not skipped"
  [ "$(printf '%s' "$json" | jq -r '.staging.visibility // "private"')" = "public" ] || continue

  cf="$dir/Containerfile"
  base_registry=$(sed -n 's/^ARG BASE_REGISTRY=//p' "$cf" | head -n 1)
  base_image=$(sed -n 's/^ARG BASE_IMAGE=//p' "$cf" | head -n 1)
  base_tag=$(sed -n 's/^ARG BASE_TAG=//p' "$cf" | head -n 1)
  go_tag=$(sed -n 's/^ARG GO_TAG=//p' "$cf" | head -n 1)
  smoke=pod
  [ ! -e "$dir/smoke/deploy.sh" ] || smoke=own-deployment
  repo="$PREFIX/$name"

  # Each lookup is run on its own line, so that one that fails stops the
  # script here; inside the jq command below its failure would be lost.
  stacks=$(stacks_of "$name")
  redhat=$(redhat_status "$name" "$(printf '%s' "$json" | jq -r '.redhat.componentId // ""')")
  rels=$(releases "$repo")
  found=$(findings "$name")
  scan=$(details "$name" "$repo" "$(printf '%s' "$rels" | jq -r '.[0].digest // ""')")
  container=$(jq -c '.container | if . == null then null else {architecture, size, created} end' "$OUT/details/$name.json")
  signature=$(jq -r '.signature' "$OUT/details/$name.json")
  printf '%s' "$json" | jq -c \
    --arg repo "$repo" \
    --arg base "$base_registry/$base_image" --arg base_digest "${base_tag#*@}" \
    --arg go "${go_tag%@*}" --arg smoke "$smoke" \
    --arg functional "$(functional_text "$dir")" \
    --argjson stacks "$stacks" --argjson redhat "$redhat" \
    --argjson releases "$rels" --argjson findings "$found" \
    --argjson scan "$scan" --argjson container "$container" --arg signature "$signature" '
    { name, displayName, summary, description,
      tags: (.tags // []),
      repository: $repo,
      upstream: { repo: .upstream.repo, version: .upstream.version, commit: .upstream.commit, license: .upstream.license },
      consumers: (.consumers // []),
      deviations: [ (.deviations // [])[] | { reason, fixes: (.fixes // []), bumps: (.bumps // []), upstreamPR } ],
      base: { image: $base, digest: $base_digest },
      toolchain: (if $go == "" then null else ("Go " + $go) end),
      checks: { smoke: $smoke, functional: (if $functional == "" then null else $functional end) },
      stacks: $stacks, redhat: $redhat, releases: $releases, findings: $findings,
      scan: $scan, container: $container, signature: $signature }' >>"$work/images.jsonl"
done
[ -s "$work/images.jsonl" ] || die "no image under $IMAGES is declared public; the site would be empty"

: >"$work/stacks.jsonl"
for sdir in "$STACKS"/*/; do
  [ -f "${sdir}images" ] || continue
  grep -v '^[[:space:]]*#' "${sdir}images" | tr -d '[:blank:]' | grep . | jq -R . |
    jq -cs --arg name "$(basename "$sdir")" '{name: $name, images: .}' >>"$work/stacks.jsonl"
done

commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
jq -n --slurpfile images "$work/images.jsonl" --slurpfile stacks "$work/stacks.jsonl" --slurpfile external "$EXTERNAL" \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg commit "$commit" --arg repo "$REPO" --argjson offline "$offline" '
  { generated: $generated, commit: $commit, source: ("https://github.com/" + $repo), offline: $offline,
    images: ($images | sort_by(.name)), stacks: $stacks, external: $external[0] }' >"$OUT/catalog.json"
echo "site-data: $(jq '.images | length' "$OUT/catalog.json") public images written to $OUT/catalog.json" >&2
