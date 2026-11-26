#!/usr/bin/env bash
# Scaffold a new certified UBI rebuild (kind: container, Go upstream):
#   scripts/new-image.sh <name> <github-owner/repo> <tag>
# <name> must be a lowercase slug (letters, digits, hyphens).
# Resolves the tag to its commit (ADR-003) so image.yaml is pinned from day one.
set -euo pipefail
NAME=${1:?name}; REPO=${2:?owner/repo}; VERSION=${3:?tag}
[[ "$NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "name '$NAME' must be a lowercase slug: letters, digits and hyphens"; exit 1; }
DIR="images/${NAME}"
[ -e "$DIR" ] && { echo "$DIR exists"; exit 1; }

# Annotated tags: prefer the dereferenced commit (^{}); lightweight tags: the tag itself
COMMIT=$(git ls-remote "https://github.com/${REPO}" "refs/tags/${VERSION}^{}" | cut -f1)
[ -n "$COMMIT" ] || COMMIT=$(git ls-remote "https://github.com/${REPO}" "refs/tags/${VERSION}" | cut -f1)
[ -n "$COMMIT" ] || { echo "tag ${VERSION} not found in ${REPO}"; exit 1; }

mkdir -p "$DIR"

cat > "$DIR/image.yaml" <<EOF
kind: container
name: ${NAME}
displayName: Stakater build of ${NAME}
summary: TODO one-line summary
description: >-
  TODO description. Rebuilt by Stakater from upstream source on Red Hat UBI.
tags: []   # TODO catalog search terms, lowercase slugs (ADR-009)
upstream:
  repo: https://github.com/${REPO}
  # renovate: datasource=github-tags depName=${REPO}
  version: ${VERSION}
  commit: ${COMMIT}
  license: TODO   # ADR-002 rule 1: Apache-2.0/MIT/BSD, else legal sign-off
build:
  prefetch: '{"type": "gomod", "path": "."}'   # typed fetchers only (ADR-003)
test:
  command: []   # TODO arguments that make the image start and exit 0, e.g. ["--help"]
smoke:
  port: 0        # TODO the port the image serves HTTP on
  path: /healthz # TODO a path that answers 2xx when the image is healthy
redhat:
  componentId: "TODO-PARTNER-CONNECT-COMPONENT-ID"
# Staged to ghcr.io/stakater/ubi/${NAME}, private by default. To make it public,
# add 'staging: {visibility: public}' in a reviewed PR (ADR-002 rev 6).
consumers: []
EOF

# The Containerfile comes from a template, not from another image.
TEMPLATE="$(dirname "$0")/templates/go/Containerfile"
[ -f "$TEMPLATE" ] || { echo "template $TEMPLATE not found"; exit 1; }
sed -e "s#__NAME__#${NAME}#g" -e "s#__REPO__#${REPO}#g" \
    -e "s#__VERSION__#${VERSION}#g" -e "s#__COMMIT__#${COMMIT}#g" \
  "$TEMPLATE" > "$DIR/Containerfile"
echo "Scaffolded $DIR (${VERSION} @ ${COMMIT})."
echo "Now fill in every TODO in $DIR/image.yaml and $DIR/Containerfile:"
echo "  licence, tags, test.command, smoke (port and path), GO_TAG (match upstream's go.mod), main package path and ldflags, labels, /licenses files, build.prefetch."
echo "Then run: make verify"
