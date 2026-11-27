#!/usr/bin/env bash
# Functional test for Dex (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once Dex is up, in the same namespace.
#
# Proves Dex does what an OpenID Connect provider must do first:
#   - it serves a discovery document whose issuer is the configured one;
#   - it serves at least one signing key at the address that document names;
#   - it does NOT serve a discovery document under a different issuer path.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
POD=${TEST_POD:-smoke}
TIMEOUT=${TEST_TIMEOUT:-90}
ISSUER=http://127.0.0.1:5556/dex # as in image.yaml's smoke config

get() { kubectl get --raw "/api/v1/namespaces/$NS/pods/$POD:5556/proxy$1"; }

discovery=$(get /dex/.well-known/openid-configuration) || {
  echo "FAIL - no OpenID Connect discovery document at /dex/.well-known/openid-configuration" >&2
  exit 1
}
issuer=$(printf '%s' "$discovery" | jq -r '.issuer // ""')
if [ "$issuer" != "$ISSUER" ]; then
  echo "FAIL - discovery document names issuer '$issuer', expected '$ISSUER'" >&2
  exit 1
fi
for field in authorization_endpoint token_endpoint jwks_uri; do
  [ -n "$(printf '%s' "$discovery" | jq -r --arg f "$field" '.[$f] // ""')" ] || {
    echo "FAIL - discovery document has no $field" >&2
    exit 1
  }
done
echo "ok   - serves OpenID Connect discovery for $ISSUER"

# Signing keys are generated at start-up; allow them a moment.
deadline=$(($(date +%s) + TIMEOUT))
while :; do
  keys=$(get /dex/keys 2>/dev/null | jq -r '(.keys // []) | length' 2>/dev/null || echo 0)
  [ "${keys:-0}" -ge 1 ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - no signing key at /dex/keys within ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep 2
done
echo "ok   - serves $keys signing key(s)"

# Control: discovery must not answer under some other issuer path.
if get /other/.well-known/openid-configuration >/dev/null 2>&1; then
  echo "FAIL - a discovery document is served under /other, which is not the issuer path" >&2
  exit 1
fi
echo "ok   - no discovery document outside the issuer path"
