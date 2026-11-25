# ADR-004: Parameterised, digest-pinned base images

- **Status:** Accepted. Revision 2, 2026-11-25. v1 is in `archive/`.
- **References:** Iron Bank `BASE_REGISTRY/BASE_IMAGE/BASE_TAG` rule; Renovate `pinDigests` (see `docs/references.md` §1)

## Decision

### Runtime base (shipped)
Every Containerfile declares, before the runtime `FROM`:
```
ARG BASE_REGISTRY=registry.access.redhat.com
ARG BASE_IMAGE=ubi9/ubi-minimal
# renovate: datasource=docker depName=registry.access.redhat.com/ubi9/ubi-minimal
ARG BASE_TAG=latest@sha256:<digest>
FROM ${BASE_REGISTRY}/${BASE_IMAGE}:${BASE_TAG}
```
- The defaults must build as-is (Iron Bank rule). CI may override `BASE_REGISTRY` to a mirror, for air-gapped or customer-side rebuilds.
- The Containerfile ARG defaults are the **single source of truth** for the base. CI passes nothing except an optional `BASE_REGISTRY` override, so `image.yaml` and the Containerfile can't drift apart.
- A `# renovate: datasource=docker depName=…` comment above `ARG BASE_TAG` lets a Renovate regex manager pin and refresh `tag@digest` (ARG-based `FROM` lines aren't reliably handled by the standard dockerfile manager; ⚠️ confirm on the first Dependency Dashboard run).
- Renovate keeps the digest current and **automerges UBI digest bumps after green CI**. This is the one exception to factory-team review (ADR-002 rule 6) and the only route for runtime-OS CVE fixes (ADR-003 §5). Each automerged bump is a new release of the image (ADR-002 rule 3).
- **Which UBI:** `ubi9/ubi-minimal` by default. `ubi9/ubi-micro` when the binary is static and needs no shell or package manager, proven with preflight and a start-up test. Every RPM in the base is something we patch under the SLA, so a static Go binary should be considered for `ubi-micro` when it is admitted. **`ubi-micro` ships no CA bundle** (checked 2026-11-25 against the image contents; `ubi-minimal` ships one), so it only suits binaries that make no outbound TLS connections. OpenCost calls cloud pricing APIs and stays on `ubi-minimal`.
- A UBI base is mandatory for certification.

### Build-stage base (not shipped)
- Language toolchain images (e.g. `docker.io/library/golang`) are allowed because they are not shipped.
- They are **pinned by digest in the same way as the runtime base**: a `# renovate:` comment above an `ARG` holding `tag@digest`. An unpinned toolchain image is an unpinned build input, which ADR-003 forbids.
- Toolchain bumps are **not automerged**. A toolchain change can alter the binary and needs a factory-team review. A patch-level bump made to fix a vulnerability is a deviation under ADR-002 rule 2.
- When upstream's required Go version is available in `registry.access.redhat.com/ubi9/go-toolset`, prefer that: it is the prerequisite for any future FIPS claim.

### Architecture
Digests are pinned for `linux/amd64` builds only (ADR-002 rule 8).

## Consequences
- \+ One base change = one Renovate PR across all images.
- \+ Customers or partners can rebuild against their own mirror with no edits.
- − The digest is the real pin; the tag is only a hint to Renovate. Moving to UBI 10 is a deliberate `BASE_IMAGE` change, never automatic.
- − Base bumps publish without a person looking. The PR pipeline is the safeguard, so it must include a start-up test of the image, not only scans.

## Enforcement
`scripts/check-image.sh` rule 10 fails any Containerfile whose base or toolchain image is not pinned by digest. ⚠️ Renovate's handling of the two `ARG` patterns is configured and validated but has not run on this repo yet.
