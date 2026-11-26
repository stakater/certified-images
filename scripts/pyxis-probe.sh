#!/usr/bin/env bash
# Ask Red Hat's Partner Connect API (Pyxis) what it returns for a component,
# without revealing any value:
#   RH_PYXIS_TOKEN=... scripts/pyxis-probe.sh <component-id>
#
# Purpose: find out whether the API hands out a component's registry
# credentials given the API key (ADR-002 rev 7). If it does, the repository
# needs one secret in total.
#
# For each candidate endpoint it prints the HTTP status. On success it prints
# the NAMES of the fields in the answer, with their types, and never a value.
# On a refusal it prints the API's own error message, with the key scrubbed.
# The API key is sent through curl's stdin config, never on a command line.
set -euo pipefail

BASE=${PYXIS_URL:-https://catalog.redhat.com/api/containers/v1}
ID=${1:?usage: pyxis-probe.sh <component-id>}
[[ "$ID" =~ ^[a-f0-9]{24}$ ]] || {
  echo "pyxis-probe: '$ID' is not a Partner Connect component ID (24 hex characters)" >&2
  exit 1
}
: "${RH_PYXIS_TOKEN:?RH_PYXIS_TOKEN must be set (from a repository secret)}"

# A key pasted with a trailing newline would break the request; strip whitespace.
KEY=$(printf '%s' "$RH_PYXIS_TOKEN" | tr -d '[:space:]')
[ -n "$KEY" ] || {
  echo "pyxis-probe: RH_PYXIS_TOKEN is empty" >&2
  exit 1
}

body=$(mktemp)
trap 'rm -f "$body"' EXIT

probe() { # <path>
  local code
  : >"$body"
  code=$(printf 'header = "X-API-KEY: %s"\n' "$KEY" |
    curl --config - -s --max-time 30 -o "$body" -w '%{http_code}' "$BASE$1" || true)
  echo "GET $1 -> HTTP ${code:-none}"
  case "$code" in
    2*) ;;
    "" | 000)
      echo "  (no answer: the request did not reach the API)"
      return
      ;;
    *)
      # A refusal. Show the API's own explanation: it is an error message, not
      # data. The key is scrubbed from it in case the API echoes it.
      if jq -e . "$body" >/dev/null 2>&1; then
        jq -r '"  \(.title // "?"): \(.detail // "(no detail)")"' "$body" | awk -v k="$KEY" '{ gsub(k, "<key>"); print }' | cut -c1-300
      fi
      return
      ;;
  esac
  if jq -e . "$body" >/dev/null 2>&1; then
    # Field names and types only. No values.
    jq -r 'paths(scalars) as $p | "  \($p | map(if type == "number" then "[]" else . end) | join("."))  (\(getpath($p) | type))"' "$body" |
      sort -u | head -n 80
  else
    echo "  (the answer is not JSON)"
  fi
}

echo "Probing component $ID. Field names and types only; values are never shown."
probe "/projects/certification/id/$ID"
probe "/projects/certification/id/$ID/secrets"
