#!/usr/bin/env bash
# Reduce a trivy JSON report to one JSON line per finding:
#   scripts/scan-findings.sh <trivy.json>
# {"id","pkg","installed","fixed","severity","class"}
# class says what kind of fix applies:
#   os      a package from the UBI base     -> bump the base digest
#   gomod   a Go module in the binary       -> bump the dependency
#   stdlib  the Go standard library         -> bump the toolchain
#   other   anything else
set -euo pipefail

REPORT=${1:?usage: scan-findings.sh <trivy.json>}
jq -e 'has("Results")' "$REPORT" >/dev/null 2>&1 || {
  echo "scan-findings: $REPORT is not a trivy JSON report" >&2
  exit 1
}
jq -c '
  .Results[]?
  | . as $r
  | (.Vulnerabilities // [])[]
  | {
      id: .VulnerabilityID,
      pkg: .PkgName,
      installed: (.InstalledVersion // ""),
      fixed: (.FixedVersion // ""),
      severity: (.Severity // ""),
      class: (
        if $r.Class == "os-pkgs" then "os"
        elif $r.Type == "gobinary" or $r.Type == "gomod" then (if .PkgName == "stdlib" then "stdlib" else "gomod" end)
        else "other" end
      )
    }
' "$REPORT"
