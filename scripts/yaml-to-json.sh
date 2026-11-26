#!/usr/bin/env bash
# Print a YAML file as JSON, using the pinned yq image:
#   scripts/yaml-to-json.sh <file.yaml>
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

FILE=${1:?usage: yaml-to-json.sh <file.yaml>}
"$ENGINE" run --rm -i "$YQ_IMAGE" -o=json '.' <"$FILE"
