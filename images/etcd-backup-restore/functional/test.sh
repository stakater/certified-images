#!/usr/bin/env bash
# Functional test for etcd-backup-restore (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has the etcd pod up, with
# this image as the backup-restore sidecar.
#
# Proves the sidecar does its jobs:
#   - initialisation: etcd only starts once the sidecar has validated the data
#     directory and served the configuration, so a ready pod already shows it;
#     here its health endpoint must also report etcd healthy;
#   - backup: asked for a full snapshot, it takes one that covers a key just
#     written, and reports it as the latest.
# Control: there is no full snapshot at that revision before one is asked for.
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

health=$(kubectl get --raw "$PROXY:8080/proxy/healthz") || {
  echo "FAIL - the sidecar does not answer /healthz" >&2
  exit 1
}
if [ "$(printf '%s' "$health" | jq -r '.health')" != "true" ]; then
  echo "FAIL - the sidecar reports etcd unhealthy: $health" >&2
  exit 1
fi
echo "ok   - the sidecar reports etcd healthy"

put=$(etcd put "{\"key\":\"$(b64 "$KEY")\",\"value\":\"$(b64 "$VALUE")\"}") || {
  echo "FAIL - etcd refused the write" >&2
  exit 1
}
revision=$(printf '%s' "$put" | jq -r '.header.revision')
latest() { kubectl get --raw "$PROXY:8080/proxy/snapshot/latest" | jq -r '.fullSnapshot.lastRevision // 0'; }
before=$(latest)
if [ "$before" -ge "$revision" ]; then
  echo "FAIL - a full snapshot at revision $before already covers revision $revision before one was asked for" >&2
  exit 1
fi
echo "ok   - control: no full snapshot covers revision $revision yet (latest: $before)"

kubectl get --raw "$PROXY:8080/proxy/snapshot/full" >/dev/null || {
  echo "FAIL - the sidecar could not take a full snapshot" >&2
  exit 1
}
after=$(latest)
if [ "$after" -lt "$revision" ]; then
  echo "FAIL - the latest full snapshot is at revision $after, expected at least $revision" >&2
  exit 1
fi
echo "ok   - the sidecar took a full snapshot covering the write (revision $after)"
