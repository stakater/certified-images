#!/usr/bin/env bash
# Prove that the factory's build mode cannot reach the network (ADR-003 §3):
#   scripts/test-hermetic.sh
#
# Builds a fixture whose only step downloads a URL, twice:
#   1. with the network: must succeed (control: the fixture and URL work)
#   2. with --network=none, as build-image.sh builds: must fail
# Without the control, a failure in 2 could be a broken fixture, not isolation.
set -euo pipefail

ENGINE=${ENGINE:-docker}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE="$ROOT/tests/fixtures/network"
TAG=localhost/stakater/hermetic-test:fixture

build() { "$ENGINE" build --no-cache "$@" -f "$FIXTURE/Containerfile" -t "$TAG" "$FIXTURE"; }
cleanup() { "$ENGINE" rmi -f "$TAG" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if ! out=$(build 2>&1); then
  printf '%s\n' "$out" | tail -n 15 >&2
  echo "test-hermetic: control failed: the fixture does not build even with the network, so this test proves nothing" >&2
  exit 1
fi
echo "ok   - control: the fixture downloads successfully with the network"

if out=$(build --network=none 2>&1); then
  echo "FAIL - a build step reached the network under --network=none" >&2
  exit 1
fi
echo "ok   - with --network=none the same step fails"
echo "test-hermetic: builds cannot reach the network"
