#!/usr/bin/env bash
# Shared by the factory scripts. Source it; do not run it.
#
# Sets ENGINE (docker unless overridden) and loads the pinned tool images from
# tools.env. A variable already set in the environment wins, so a caller can
# override one tool without editing the file.

ENGINE=${ENGINE:-docker}

_lib_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[ -f "$_lib_root/tools.env" ] || {
  echo "lib.sh: $_lib_root/tools.env not found" >&2
  exit 1
}
while IFS='=' read -r _key _value; do
  case "$_key" in '' | \#*) continue ;; esac
  [ -n "${!_key:-}" ] || export "$_key=$_value"
done <"$_lib_root/tools.env"
unset _lib_root _key _value

# crane <args...>: run crane from its pinned image, with the registry
# credentials of the current container-engine login if there is one
# (~/.docker/config.json, or the file named by REGISTRY_AUTH_FILE).
# REGISTRY_INSECURE=1 allows a plain-HTTP registry; TOOL_NETWORK joins a
# container network. Both are for the local rehearsal.
crane() {
  local auth mounts=()
  auth=${REGISTRY_AUTH_FILE:-${DOCKER_CONFIG:-$HOME/.docker}/config.json}
  [ -f "$auth" ] && mounts=(-v "$auth:/auth/config.json:ro" -e DOCKER_CONFIG=/auth)
  "$ENGINE" run --rm ${TOOL_NETWORK:+--network "$TOOL_NETWORK"} ${mounts[@]+"${mounts[@]}"} \
    "$CRANE_IMAGE" ${REGISTRY_INSECURE:+--insecure} "$@"
}
