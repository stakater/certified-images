# ADR-006: Stakater-owned upstreams build in their own repo

- **Status:** Proposed. Edited 2026-11-25 during review, before first acceptance.
- **References:** OpenShift productisation: upstream repos carry `Dockerfile.rhel` next to the community Dockerfile; build metadata stays separate (`ocp-build-data`). See `docs/references.md` §2. GitHub's guide to reusable workflows with artifact attestations.

## Context
template-operator-v2, dex-config-operator, MTO components and Reloader are **our** code. Copying their build into `certified-images` would split ownership: the product team changes code, while a different repo decides how it ships.

## Decision
- Stakater-owned repos carry a `Containerfile.ubi` (hermetic, ADR-003/004 rules) next to their existing Dockerfile. Product teams own it.
- `certified-images` exposes the pipeline as a **reusable workflow** (`on: workflow_call`, inputs: `containerfile`, `image-yaml`). Product repos call it, so there is one pipeline with many callers.
- **The pipeline is a reusable workflow from the first version**, with this repo's own `images/**` builds as its first caller. Two reasons:
  - the signing identity customers verify against is the reusable workflow's, so it stays the same when product repos start calling it. Extracting it later would change the identity in every published verify command;
  - a reusable workflow is what GitHub's guide requires for SLSA Build L3 (ADR-007).
- `certified-images/images/` holds **third-party** upstreams only.
- Each product repo keeps its own `image.yaml` (same schema), so Renovate, CVE gate and preflight behave identically.
- **Same rules, different owner.** ADR-002 rules 3 (naming and versions), 4 (patch SLA) and 8 (architectures) apply to product-owned images. The product team owns meeting them; the factory team owns the pipeline. Product repos also build their OLM bundle; this repo does not (ADR-005).
- Callers pin the reusable workflow to a released major tag (`@v1`).

## Consequences
- \+ Product teams fix their own CVEs; the factory team owns the pipeline, not every image.
- \+ One signing identity for every image the factory pipeline builds, wherever the source lives.
- − The reusable workflow is an API from day one; breaking changes need a new major tag.
- − Verification commands must name the workflow, not only the repo: `cosign` with an identity that matches the reusable workflow at a release tag, and `gh attestation verify --signer-workflow stakater/certified-images/.github/workflows/<file>`. The README's current regex pins `@refs/heads/main` and must change when the workflow is written (story P.1).

## Exception: incubating here first
Reloader v2 is built from `images/reloader` in this repository, by the owner's decision of 2026-11-26, although it is Stakater's own code. The pipeline cannot yet be called from another repository, and waiting for that would have delayed the first own-product image. It moves to the Reloader repository, with its `Containerfile.ubi`, once the external-caller story is done. Until then the cost this ADR warns about applies: the code and the recipe that ships it live in different places.

## Status of implementation
Nothing exists yet. The reusable workflow is written in story P.1. The first external caller (template-operator-v2) is a later story; this ADR is accepted when that caller's team has reviewed it.
