#!/usr/bin/env bash
# Prove that the smoke test can fail:
#   scripts/test-smoke.sh
#
# Builds two deliberately broken fixture images and runs the smoke test on
# each. Both must be rejected, each for its own reason:
#   smoke-writes-root    writes to the root filesystem at start-up
#   smoke-never-listens  stays up but never serves on the declared port
# A smoke test that passes these would pass anything. The matching positive
# case is a real image passing `make smoke`.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

check() { # <fixture> <timeout> <pattern the failure must match>
  local fixture=$1 timeout=$2 pattern=$3 ref="localhost/stakater/$1:fixture" out
  "$ENGINE" build -q -f "$ROOT/tests/fixtures/$fixture/Containerfile" -t "$ref" "$ROOT/tests/fixtures/$fixture" >/dev/null
  if out=$(SMOKE_TIMEOUT=$timeout SMOKE_CLUSTER="smoke-selftest" "$ROOT/scripts/smoke-kind.sh" "$ref" "$ROOT/tests/fixtures/$fixture" 2>&1); then
    printf '%s\n' "$out" | tail -n 20 >&2
    echo "FAIL - $fixture passed the smoke test; it must be rejected" >&2
    exit 1
  fi
  if ! printf '%s' "$out" | grep -Eq -- "$pattern"; then
    printf '%s\n' "$out" | tail -n 30 >&2
    echo "FAIL - $fixture failed, but not for the expected reason (/$pattern/)" >&2
    exit 1
  fi
  "$ENGINE" rmi -f "$ref" >/dev/null 2>&1 || true
  echo "ok   - $fixture is rejected: $(printf '%s' "$out" | grep -E '^FAIL - ' | head -n1 | sed 's/^FAIL - //')"
}

check smoke-writes-root 60 'exited before becoming Ready|did not become Ready'
check smoke-never-listens 20 'did not become Ready within 20s'
echo "test-smoke: the smoke test rejects images that do not work"
