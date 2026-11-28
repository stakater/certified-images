#!/usr/bin/env bash
# Functional test for etcd-wrapper (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has the etcd pod up, with
# this image as the etcd container.
#
# Proves the etcd it starts does what etcd is for: a key that is written can be
# read back with the same value.
# Control: the key does not exist before it is written, so a pass cannot come
# from something left behind.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
POD=etcd-smoke-0
PROXY="/api/v1/namespaces/$NS/pods/$POD"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
etcd() { # etcd <put|range> <json body>: etcd's HTTP API, through the API server
  printf '%s' "$2" >"$work/body.json"
  kubectl create --raw "$PROXY:2379/proxy/v3/kv/$1" -f "$work/body.json"
}
KEY=smoke-key
VALUE=smoke-value-$$

before=$(etcd range "{\"key\":\"$(b64 "$KEY")\"}") || {
  echo "FAIL - etcd does not answer a read" >&2
  exit 1
}
if [ "$(printf '%s' "$before" | jq -r '.count // "0"')" != "0" ]; then
  echo "FAIL - key $KEY already exists before it is written" >&2
  exit 1
fi
echo "ok   - control: etcd answers, and the key does not exist yet"

etcd put "{\"key\":\"$(b64 "$KEY")\",\"value\":\"$(b64 "$VALUE")\"}" >/dev/null || {
  echo "FAIL - etcd refused the write" >&2
  exit 1
}
after=$(etcd range "{\"key\":\"$(b64 "$KEY")\"}")
got=$(printf '%s' "$after" | jq -r '.kvs[0].value // ""' | base64 -d 2>/dev/null || true)
if [ "$got" != "$VALUE" ]; then
  echo "FAIL - read back '$got', expected '$VALUE'" >&2
  exit 1
fi
echo "ok   - a key written to etcd is read back with the same value"
