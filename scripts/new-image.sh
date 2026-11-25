#!/usr/bin/env bash
# Scaffold a new certified UBI rebuild (kind: container):
#   scripts/new-image.sh <name> <github-owner/repo> <tag>
# Resolves the tag to its commit (ADR-003) so image.yaml is pinned from day one.
set -euo pipefail
NAME=${1:?name}; REPO=${2:?owner/repo}; VERSION=${3:?tag}
DIR="images/${NAME}"
[ -e "$DIR" ] && { echo "$DIR exists"; exit 1; }

# Annotated tags: prefer the dereferenced commit (^{}); lightweight tags: the tag itself
COMMIT=$(git ls-remote "https://github.com/${REPO}" "refs/tags/${VERSION}^{}" | cut -f1)
[ -n "$COMMIT" ] || COMMIT=$(git ls-remote "https://github.com/${REPO}" "refs/tags/${VERSION}" | cut -f1)
[ -n "$COMMIT" ] || { echo "tag ${VERSION} not found in ${REPO}"; exit 1; }

mkdir -p "$DIR"
SUFFIX=$(echo "$NAME" | tr '[:lower:]-' '[:upper:]_')

cat > "$DIR/image.yaml" <<EOF
kind: container
name: ${NAME}
displayName: Stakater build of ${NAME}
summary: TODO one-line summary
description: >-
  TODO description. Rebuilt by Stakater from upstream source on Red Hat UBI.
upstream:
  repo: https://github.com/${REPO}
  # renovate: datasource=github-tags depName=${REPO}
  version: ${VERSION}
  commit: ${COMMIT}
  license: TODO   # ADR-002 rule 1: Apache-2.0/MIT/BSD, else legal sign-off
build:
  goVersion: "TODO"   # from upstream go.mod
  prefetch: '{"type": "gomod", "path": "."}'   # typed fetchers only (ADR-003)
redhat:
  componentId: "TODO-PARTNER-CONNECT-COMPONENT-ID"
  secretSuffix: ${SUFFIX}
consumers: []
EOF

sed -e "s#opencost/opencost#${REPO}#g" -e "s#OpenCost#${NAME}#g" -e "s#stakater/opencost#stakater/${NAME}#g" \
    -e "s#^ARG UPSTREAM_VERSION=.*#ARG UPSTREAM_VERSION=${VERSION}#" \
    -e "s#^ARG UPSTREAM_COMMIT=.*#ARG UPSTREAM_COMMIT=${COMMIT}#" \
  images/opencost/Containerfile > "$DIR/Containerfile"
echo "Scaffolded $DIR (${VERSION} @ ${COMMIT})."
echo "Now fix: build stage (WORKDIR, go build path, ldflags), labels, /licenses paths, build.prefetch."
