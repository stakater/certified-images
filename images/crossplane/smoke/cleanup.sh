#!/usr/bin/env bash
# Remove what smoke/deploy.sh created (scripts/smoke-test.sh runs this last).
# The namespace is deleted by the smoke test itself. Crossplane's CRDs are left
# in place: on the throwaway cluster used for pull requests they go with the
# cluster, and deleting CRDs on a shared cluster is not something a test does.
set -uo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
kubectl delete provider.pkg.crossplane.io smoke-provider-nop --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl delete deploymentruntimeconfig.pkg.crossplane.io smoke-restricted --ignore-not-found --wait=false >/dev/null 2>&1 || true
helm uninstall crossplane-smoke --namespace "$NS" >/dev/null 2>&1 || true
