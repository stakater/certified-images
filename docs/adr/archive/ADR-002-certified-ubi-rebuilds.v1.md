# ADR-002: Certified UBI rebuilds of upstream OSS images

- **Status:** Accepted (pilot: OpenCost)
- **Date:** 2026-11-25
- **Owner:** Rasheed Amir (Stakater) — factory owner TBD

## Context
Stakater operators (MTO first; Reloader Enterprise, others later) deploy upstream OSS images (OpenCost, Dex, …) pulled from ghcr.io/quay.io by tag. This breaks:
1. **Air-gapped installs**: `oc-mirror` only mirrors images in the bundle's `relatedImages`; tag refs can't be remapped by IDMS.
2. **Red Hat certification policy**: every operand must be a certified image.

There is no Red Hat equivalent for several of these images, and we will need the same treatment for many products.

## Decision
Run one repository, `stakater/certified-images`, that rebuilds selected upstream images **from source** on Red Hat UBI and certifies them in Partner Connect, using the same pipeline for every image:

`image.yaml + Containerfile → build → SBOM (syft) → CVE gate (trivy) → preflight → push quay.io/redhat-isv-containers/<pid> → cosign sign + SBOM attest → preflight --submit → auto-publish`

Consumers reference the results **by digest** via `RELATED_IMAGE_*` and the CSV `relatedImages`.

## Rules
1. **Admission:** rebuild only when (a) no Red Hat-provided image exists, (b) the licence is permissive (Apache-2.0/MIT/BSD), (c) upstream is actively maintained, and (d) a Stakater product deploys it. Otherwise use the Red Hat image or the customer's own (External mode).
2. **Build from source**, not re-tagged upstream binaries.
3. **Naming:** "Stakater build of <Project>". Keep upstream LICENSE/NOTICE in `/licenses`. Don't use upstream logos.
4. **Patch SLA:** fixable CRITICAL CVEs within 7 days; upstream minor releases within 30 days. Renovate opens the PRs; UBI digest bumps automerge after green CI.
5. **One Partner Connect component per image**, Red Hat Container Registry distribution, one export questionnaire covering new images (EAR99/OAM where true).

## Consequences
- + Air-gap and certification are solved once, reused per product.
- + Our CVE posture and SBOM/signing claims become verifiable.
- − Every admitted image is a permanent patching commitment, which the admission rule must keep small.
- − Partner Connect component creation and export approval stay manual (once per image).

## Pilot scope (OpenCost)
- [x] `images/opencost/` Containerfile + image.yaml (upstream v1.121.5, Go 1.27.3)
- [x] Workflow: build, SBOM, CVE gate, preflight dry-run; push/sign/submit on main
- [ ] Partner Connect component + export questionnaire → fill `redhat.componentId`
- [ ] Repo secrets: `RH_PYXIS_TOKEN_OPENCOST`, `RH_REGISTRY_USER_OPENCOST`, `RH_REGISTRY_PASSWORD_OPENCOST`
- [ ] First certified publish
- [ ] MTO consumes by digest (`RELATED_IMAGE_OPENCOST` + CSV `relatedImages`)

## Next images
Dex, then template-operator-v2 and dex-config-operator (ours, same pipeline minus upstream clone).
