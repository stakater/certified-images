#!/usr/bin/env bash
# Functional test for Prometheus (docs/planning/f1-functional-tests.md).
# Run by scripts/smoke-test.sh once smoke/deploy.sh has it up as pod "prometheus".
#
# Proves Prometheus does its job:
#   - it scrapes a target (itself, per the configuration in the image), stores
#     the result and answers a query for it;
#   - it serves its web UI, which shows the UI built in this image's build was
#     put into the binary.
# Control: a query for a job that does not exist returns nothing, so a result
# for the real job is not just "every query returns something".
set -euo pipefail

NS=${TEST_NAMESPACE:?TEST_NAMESPACE must be set}
TIMEOUT=${TEST_TIMEOUT:-90}
PROXY="/api/v1/namespaces/$NS/pods/prometheus:9090/proxy"

# query <PromQL, URL-encoded>: the value of the first result, or nothing.
query() { kubectl get --raw "$PROXY/api/v1/query?query=$1" | jq -r '.data.result[0].value[1] // ""'; }

kubectl get --raw "$PROXY/api/v1/query?query=vector(1)" >/dev/null || {
  echo "FAIL - Prometheus does not answer queries" >&2
  exit 1
}
none=$(query 'up%7Bjob%3D%22no-such-job%22%7D')
if [ -n "$none" ]; then
  echo "FAIL - a query for a job that does not exist returned '$none'" >&2
  exit 1
fi
echo "ok   - control: a query for a job that does not exist returns nothing"

deadline=$(($(date +%s) + TIMEOUT))
until [ "$(query 'up%7Bjob%3D%22prometheus%22%7D')" = "1" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL - up{job=\"prometheus\"} was not 1 within ${TIMEOUT}s: the scrape did not succeed or was not stored" >&2
    exit 1
  fi
  sleep 3
done
echo "ok   - it scraped its target, stored the sample and answers the query: up{job=\"prometheus\"} is 1"

page=$(kubectl get --raw "$PROXY/query") || {
  echo "FAIL - the web UI is not served at /query (was it built into the binary?)" >&2
  exit 1
}
case "$page" in
  *'<div id="root"'*) ;;
  *)
    echo "FAIL - /query does not return the web UI's page" >&2
    exit 1
    ;;
esac
asset=$(grep -o '/assets/[^"]*\.js' <<<"$page" | sed -n '1p')
[ -n "$asset" ] || {
  echo "FAIL - the UI page names no script" >&2
  exit 1
}
kubectl get --raw "$PROXY$asset" >/dev/null || {
  echo "FAIL - the UI's script $asset is not served" >&2
  exit 1
}
echo "ok   - the web UI built into the binary is served, page and script"
