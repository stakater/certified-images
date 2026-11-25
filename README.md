# certified-images

Stakater builds of upstream OSS, rebuilt from source on Red Hat UBI, certified for OpenShift, and shipped with SBOM, signatures and provenance. Used by Stakater products (MTO, SCO, Reloader Enterprise) so they install in **air-gapped** clusters and meet Red Hat's operand certification rule.

**We build on existing, proven implementations rather than inventing our own:** Iron Bank, OpenShift ART, Konflux/Hermeto, Chainguard, Crossplane packaging. See [docs/references.md](docs/references.md).

## Decisions
| ADR | Decision |
|---|---|
| [001](docs/adr/ADR-001-record-architecture-decisions.md) | How we record decisions: ADR format, revise or supersede, ⚠️ for unverified claims |
| [002](docs/adr/ADR-002-certified-ubi-rebuilds.md) | Umbrella: one factory, admission, allowed deviations, versions, patch SLA, governance |
| [003](docs/adr/ADR-003-hermetic-builds.md) | Commit-pinned source, Hermeto prefetch, `--network=none`, dependency-only patches |
| [004](docs/adr/ADR-004-base-images.md) | `BASE_REGISTRY/BASE_IMAGE/BASE_TAG`, digest-pinned UBI and toolchain, Renovate |
| [005](docs/adr/ADR-005-artifact-kinds-crossplane.md) | `kind: container / xpkg`; SCO Crossplane wrappers (Proposed) |
| [006](docs/adr/ADR-006-stakater-owned-upstreams.md) | Our own repos carry `Containerfile.ubi` + call the reusable workflow (Proposed) |
| [007](docs/adr/ADR-007-build-platform.md) | GitHub Actions; Konflux re-evaluated when a trigger fires |
| [008](docs/adr/ADR-008-supply-chain-evidence.md) | SBOMs, cosign, provenance, CVE gate + daily re-scan, OpenVEX exceptions |

## Layout
```
images/<name>/image.yaml        # kind, upstream repo+tag+commit, prefetch input, Partner Connect ID
images/<name>/Containerfile     # hermetic build stage + parameterised UBI runtime stage
images/<name>/vex.openvex.json  # optional CVE exceptions (ADR-008)
images/<name>/patches/*.patch   # optional dependency-only patches (ADR-003 §6)
.github/workflows/build-certify.yaml
.github/CODEOWNERS              # factory team merges to main (= publish)
renovate.json                   # upstream tag+commit, UBI digest
Makefile, tests/                # make verify: lint + image.yaml rules + script tests
scripts/new-image.sh, scripts/check-image.sh
docs/adr/, docs/references.md
```

## Pipeline
PR: pinned clone (fails if the tag moved) → Hermeto prefetch → build with network off → syft SBOM → VEX expiry check → trivy gate (fixable CRITICAL and HIGH) → preflight dry run.
main adds: push to `quay.io/redhat-isv-containers/<componentId>` → cosign sign and SBOM attestations (image + dependencies) → build provenance → `preflight --submit`. Partner Connect then auto-publishes.

## Add an image
1. `scripts/new-image.sh <name> <owner/repo> <tag>`. This fills in the tag's commit; then edit the build stage and `build.prefetch`. Run `make verify` until it passes: it will reject the scaffold until the licence and Go version are filled in.
2. Check the admission rules (ADR-002 rule 1). Record the licence in `image.yaml`.
3. Partner Connect → product → Add component → Container image, **UBI**, **Red Hat Container Registry**. Put the component ID in `image.yaml`.
4. Submit the export questionnaire (batch several new components in one form).
5. Add repo secrets `RH_PYXIS_TOKEN_<SUFFIX>`, `RH_REGISTRY_USER_<SUFFIX>`, `RH_REGISTRY_PASSWORD_<SUFFIX>`.
6. Open a PR. The factory team merges, and the pipeline certifies.

## Consuming
- **Operators:** CSV `relatedImages` + `RELATED_IMAGE_<NAME>`, by digest. Never upstream tags.
- **Crossplane (SCO):** install `stakater/<provider>` packages by digest. Air-gapped customers add an `ImageConfig` with `rewriteImage.prefix` to their mirror (Crossplane ≥ 1.20).

## Verify (customers)
```
cosign verify <ref>@sha256:... \
  --certificate-identity-regexp '^https://github.com/stakater/certified-images/.github/workflows/build-certify.yaml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation --type spdxjson <same flags> <ref>@sha256:...
gh attestation verify oci://<ref>@sha256:... --repo stakater/certified-images
```

## Status
**Nothing has been built yet, and the pipeline does not exist yet.** `.github/workflows/build-certify.yaml` and `.github/CODEOWNERS` are described below and in the ADRs but are not in the repo; story P.1 in [docs/roadmap.md](docs/roadmap.md) writes them. The Pipeline, Add an image and Verify sections describe the design, not something you can run today. How we work: [docs/method.md](docs/method.md).

## Before the first production run (unverified items)
Check these on the first CI run:
- [ ] Pin `HERMETO_IMAGE`, preflight, trivy-action and other actions by digest or version.
- [ ] Hermeto `gomod` prefetch works with upstream's `go 1.27.3` directive and its local `replace` modules (`./core`, `./modules/*`).
- [ ] Hermeto dependency SBOM file name (`bom.json` assumed).
- [ ] preflight flag `--certification-component-id` vs `--certification-project-id` on the pinned version.
- [ ] `TRIVY_VEX` env is honoured by the pinned trivy.
- [ ] Renovate pins the UBI base digest on its first run (Dependency Dashboard).
- [ ] `ubi9/ubi-minimal` CA bundle is enough for OpenCost's outbound TLS (cloud pricing APIs).

## Local build (mirrors CI)
```
git clone --depth 1 --branch v1.121.5 https://github.com/opencost/opencost .ctx/src && rm -rf .ctx/src/.git
cp images/opencost/Containerfile .ctx/
H="podman run --rm -v $PWD/.ctx:$PWD/.ctx:z -w $PWD/.ctx ghcr.io/hermetoproject/hermeto:latest"
$H fetch-deps --source ./src --output ./hermeto-output '{"type": "gomod", "path": "."}'
$H generate-env ./hermeto-output -o ./hermeto.env --for-output-dir /tmp/hermeto-output
$H inject-files ./hermeto-output --for-output-dir /tmp/hermeto-output
podman build --network=none -t opencost:test .ctx
```
