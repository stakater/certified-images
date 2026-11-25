# ADR-002: Certified UBI rebuilds of upstream OSS (umbrella)

- **Status:** Accepted (pilot: OpenCost). Revision 2, 2026-11-25. v1 is in `archive/`.
- **Owner:** Rasheed Amir (Stakater). Factory owner TBD.
- **References:** Iron Bank, OpenShift ART, Konflux, Chainguard (see `docs/references.md`).

## Context
Stakater products deploy upstream OSS (OpenCost, Dex, Crossplane providers, …) pulled from ghcr.io/quay.io/xpkg.upbound.io by tag. This breaks two things:
1. **Air-gapped installs.** `oc-mirror` only mirrors images listed in the bundle's `relatedImages`, and IDMS only remaps digest references.
2. **Red Hat certification.** Every operand must be a certified image.

MTO needs this now. SCO needs it for many Crossplane providers and functions. Reloader Enterprise will need it later.

## Decision
One repository, `stakater/certified-images`, with one pipeline that rebuilds admitted upstreams **from source** on Red Hat UBI, certifies them in Partner Connect, and publishes them with SBOM, signatures and provenance. We follow existing implementations rather than designing our own:

| Concern | Decision | Follows | ADR |
|---|---|---|---|
| Builds without network, pinned sources | Hermeto prefetch + `--network=none` | Iron Bank, Konflux/Hermeto | 003 |
| Swappable, pinned bases | `BASE_REGISTRY/BASE_IMAGE/BASE_TAG` + digests | Iron Bank | 004 |
| Containers, Crossplane packages, bundles | `kind:` in `image.yaml` | Crossplane xpkg tooling | 005 |
| Stakater-owned upstreams | `Containerfile.ubi` in their own repo, reusable workflow | OpenShift `Dockerfile.rhel` | 006 |
| Build platform | GitHub Actions now, Konflux later | Konflux | 007 |
| Supply-chain evidence | SBOM, cosign, SLSA provenance, VEX exceptions | Chainguard, Iron Bank VAT | 008 |

Consumers reference results **by digest** only: CSV `relatedImages` + `RELATED_IMAGE_*` for operators; xpkg digests + `ImageConfig` for Crossplane.

## Rules
1. **Admission.** Rebuild only when all four hold: (a) no Red Hat-provided image exists, (b) the licence is permissive (Apache-2.0/MIT/BSD; anything else needs legal sign-off), (c) upstream is maintained (release in the last 6 months), and (d) a Stakater product deploys it. Otherwise use the Red Hat image or the customer's own (External mode).
2. **Build from source** at a pinned commit (ADR-003). Never re-tag upstream binaries.
3. **Naming.** "Stakater build of <Project>"; registry path `stakater/<name>`. Keep upstream LICENSE/NOTICE in `/licenses`. Don't use upstream logos or marks.
4. **Patch SLA.** Fixable CRITICAL CVEs within 7 days, HIGH within 30 days; upstream minor releases within 30 days. Renovate opens PRs, and UBI digest bumps automerge after green CI.
5. **Partner Connect.** One component per image, Red Hat Container Registry distribution. Batch new images into one export questionnaire.
6. **Governance.** CODEOWNERS on `images/**` and `.github/**`: only the factory team merges to `main`, which publishes (Iron Bank model). Anyone may open a PR.
7. **No invention.** A new pattern needs a reference in `docs/references.md`, or an ADR that names the gap as a risk.

## Consequences
- \+ Air gap and certification are solved once and reused across MTO, SCO and Reloader.
- \+ CVE, SBOM, signing and provenance claims become verifiable, which is a sellable sovereign-supply-chain story.
- − Every admitted image is a permanent patching commitment; the admission rule must keep the set small.
- − Partner Connect component creation and export approval stay manual (once per image).

## Pilot scope (OpenCost)
- [x] `images/opencost/` hermetic Containerfile and image.yaml (v1.121.5 @ `32dbf049c84c66db1efeb9fc9a98e5042f076cf1`, Go 1.27.3)
- [x] Workflow: prefetch → offline build → SBOM → CVE gate → preflight dry run; push/sign/submit on main
- [ ] First green CI run (not yet built: no container engine in the authoring environment)
- [ ] Partner Connect component + export questionnaire → `redhat.componentId`
- [ ] Repo secrets `RH_PYXIS_TOKEN_OPENCOST`, `RH_REGISTRY_USER_OPENCOST`, `RH_REGISTRY_PASSWORD_OPENCOST`
- [ ] First certified publish → MTO consumes by digest

## Next
Dex → template-operator-v2 and dex-config-operator (ADR-006 path) → first SCO Crossplane provider (ADR-005 path).
