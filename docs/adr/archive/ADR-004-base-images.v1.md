# ADR-004: Parameterised, digest-pinned base images

- **Status:** Accepted
- **Date:** 2026-11-25
- **References:** Iron Bank `BASE_REGISTRY/BASE_IMAGE/BASE_TAG` rule; Renovate `pinDigests` (see `docs/references.md` §1)

## Decision
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
- Renovate keeps the digest current and automerges UBI digest bumps after green CI. This is the only route for runtime-OS CVE fixes (ADR-003 §5).
- **Runtime base:** `ubi9/ubi-minimal` by default; `ubi9/ubi-micro` when the binary is static and needs no shell or package manager (prove it with preflight first). A UBI base is mandatory for certification.
- **Build-stage base:** language toolchain images (e.g. `docker.io/library/golang`) are allowed because they are not shipped. They are digest-pinned too. When upstream's required Go version is available in `registry.access.redhat.com/ubi9/go-toolset`, prefer that: it is the prerequisite for any future FIPS claim.

## Consequences
- \+ One base change = one Renovate PR across all images.
- \+ Customers or partners can rebuild against their own mirror with no edits.
- − The digest is the real pin; the tag is only a hint to Renovate. Moving to UBI 10 is a deliberate `BASE_IMAGE` change, never automatic.

⚠️ The first Renovate run fills in the digest (no registry access from the authoring environment).
