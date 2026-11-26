#!/usr/bin/env bash
# Check an image's labels against the label policy (ADR-009):
#   scripts/check-labels.sh <labels.json> <image.json>
#
# <labels.json>  the image's labels as a JSON object
# <image.json>   its image.yaml as JSON (scripts/yaml-to-json.sh)
# Pure: needs jq only, so it is tested without building anything.
#
# Optional expectations, checked when set:
#   EXPECT_RELEASE      the release number this build was given
#   EXPECT_VCS_REF      the commit of the repository that built it
#   EXPECT_BASE_DIGEST  the base image digest pinned in the Containerfile
#   SOURCE_REPO         the building repository (default: this one)
set -euo pipefail

LABELS=${1:?usage: check-labels.sh <labels.json> <image.json>}
IMAGE=${2:?usage: check-labels.sh <labels.json> <image.json>}
SOURCE_REPO=${SOURCE_REPO:-https://github.com/stakater/certified-images}

problems=$(jq -r -n --slurpfile l "$LABELS" --slurpfile i "$IMAGE" \
  --arg source "$SOURCE_REPO" --arg release "${EXPECT_RELEASE:-}" \
  --arg vcs "${EXPECT_VCS_REF:-}" --arg base "${EXPECT_BASE_DIGEST:-}" '
  ($l[0] // {}) as $L | $i[0] as $I
  | ($I.name) as $name
  | ("\($source)/tree/main/images/\($name)") as $url
  | def has($k): (($L[$k] // "") != "");
    def need($k): if has($k) then empty else "\($k): missing or empty" end;
    def eq($k; $want): if ($L[$k] // "") == $want then empty
      else "\($k): expected \"\($want)\", got \"\($L[$k] // "")\"" end;
    def rfc3339: test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$");

    # 1. Red Hat required
    (["name","vendor","maintainer","version","release","summary","description"][] | need(.)),
    eq("name"; "stakater/\($name)"),
    eq("vendor"; "Stakater AB"),
    eq("version"; $I.upstream.version),
    eq("summary"; $I.summary),
    eq("description"; $I.description),
    (["name","vendor","maintainer"][] | . as $k
      | if (($L[$k] // "") | test("red ?hat"; "i")) then "\($k): must not use a Red Hat trademark (\"\($L[$k])\")" else empty end),
    (if $release != "" then eq("release"; $release) else empty end),

    # 2. What built it
    eq("org.opencontainers.image.source"; $source),
    need("org.opencontainers.image.revision"),
    (if (($L["org.opencontainers.image.revision"] // "") | test("^[a-f0-9]{40}(-dirty)?$")) then empty
      else "org.opencontainers.image.revision: must be the commit that built the image, got \"\($L["org.opencontainers.image.revision"] // "")\"" end),
    eq("vcs-ref"; ($L["org.opencontainers.image.revision"] // "")),
    eq("vcs-type"; "git"),
    (if $vcs != "" then eq("org.opencontainers.image.revision"; $vcs) else empty end),
    (if (($L["org.opencontainers.image.created"] // "") | rfc3339) then empty
      else "org.opencontainers.image.created: must be an RFC 3339 time, got \"\($L["org.opencontainers.image.created"] // "")\"" end),
    eq("build-date"; ($L["org.opencontainers.image.created"] // "")),
    eq("org.opencontainers.image.url"; $url),
    eq("url"; $url),

    # 3. What is inside
    eq("org.opencontainers.image.version"; $I.upstream.version),
    eq("org.opencontainers.image.licenses"; $I.upstream.license),
    eq("com.stakater.upstream.repo"; $I.upstream.repo),
    eq("com.stakater.upstream.version"; $I.upstream.version),
    eq("com.stakater.upstream.commit"; $I.upstream.commit),

    # 4. What it is based on
    (if (($L["org.opencontainers.image.base.name"] // "") | test("^[^/ ]+/[^ ]+$")) then empty
      else "org.opencontainers.image.base.name: must be the base image reference, got \"\($L["org.opencontainers.image.base.name"] // "")\"" end),
    (if (($L["org.opencontainers.image.base.digest"] // "") | test("^sha256:[a-f0-9]{64}$")) then empty
      else "org.opencontainers.image.base.digest: must be sha256:<digest>, got \"\($L["org.opencontainers.image.base.digest"] // "")\"" end),
    (if $base != "" then eq("org.opencontainers.image.base.digest"; $base) else empty end),

    # 5. Descriptive
    (if (($L["org.opencontainers.image.title"] // "") | startswith("Stakater build of ")) then empty
      else "org.opencontainers.image.title: must start with \"Stakater build of \", got \"\($L["org.opencontainers.image.title"] // "")\"" end),
    eq("org.opencontainers.image.description"; $I.description),
    eq("org.opencontainers.image.vendor"; "Stakater AB"),
    need("io.k8s.display-name"),
    need("io.k8s.description"),
    eq("io.openshift.tags"; (($I.tags // []) | join(",")))
')

if [ -n "$problems" ]; then
  printf '%s\n' "$problems" | sed 's/^/FAIL - label /' >&2
  echo "check-labels: labels do not follow ADR-009" >&2
  exit 1
fi
echo "ok   - labels follow ADR-009 (what built it, what is inside, what it is based on)"
