#!/usr/bin/env bash
# Functional test for kcp (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has kcp up as pod "kcp".
#
# Proves kcp does its job: it creates a workspace on request, the workspace
# becomes Ready, and it is a logical cluster of its own that answers the
# Kubernetes API (it has a "default" namespace).
# Control: the workspace does not exist before it is created, so a pass cannot
# come from something left behind.
#
# Talks to kcp through "kubectl port-forward", with the admin kubeconfig kcp
# writes into its data directory.
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
WS=smoke

work=$(mktemp -d)
pf_pid=""
cleanup() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" 2>/dev/null || true
    wait "$pf_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

kubectl -n "$NS" exec kcp -- cat /data/admin.kubeconfig >"$work/admin.kubeconfig" || {
  echo "FAIL - kcp did not write its admin kubeconfig" >&2
  exit 1
}

kubectl -n "$NS" port-forward pod/kcp :6443 >"$work/pf.log" 2>&1 &
pf_pid=$!
port=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  port=$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9]*\) .*/\1/p' "$work/pf.log" | head -n 1)
  [ -z "$port" ] || break
  sleep 1
done
[ -n "$port" ] || {
  echo "FAIL - could not forward a port to kcp" >&2
  cat "$work/pf.log" >&2
  exit 1
}

# kcp's serving certificate is issued for its own addresses; "localhost" is
# among them.
kcp() { # kcp <logical cluster path> <kubectl arguments...>
  local cluster=$1
  shift
  kubectl --kubeconfig "$work/admin.kubeconfig" --server "https://127.0.0.1:$port/clusters/$cluster" \
    --tls-server-name localhost "$@"
}

if kcp root get workspace "$WS" >/dev/null 2>&1; then
  echo "FAIL - workspace $WS already exists before it is created" >&2
  exit 1
fi
kcp root get workspaces >/dev/null 2>&1 || {
  echo "FAIL - kcp does not serve the workspaces API in the root workspace" >&2
  exit 1
}
echo "ok   - control: kcp serves workspaces, and workspace $WS does not exist yet"

kcp root apply -f - >/dev/null <<YAML
apiVersion: tenancy.kcp.io/v1alpha1
kind: Workspace
metadata:
  name: $WS
spec:
  type:
    name: universal
    path: root
YAML

deadline=$(($(date +%s) + TIMEOUT))
while :; do
  phase=$(kcp root get workspace "$WS" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [ "$phase" = "Ready" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - workspace $WS did not become Ready within ${TIMEOUT}s (phase '${phase}')" >&2
    exit 1
  fi
  sleep 2
done
echo "ok   - kcp created workspace $WS and it is Ready"

kcp "root:$WS" get namespace default >/dev/null || {
  echo "FAIL - workspace $WS does not answer the Kubernetes API as a cluster of its own" >&2
  exit 1
}
echo "ok   - the workspace is a logical cluster of its own: it has a default namespace"
