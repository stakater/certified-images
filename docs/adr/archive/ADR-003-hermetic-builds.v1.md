# ADR-003: Hermetic, pinned-source builds

- **Status:** Accepted
- **Date:** 2026-11-25
- **References:** Iron Bank Dockerfile requirements (no internet in the build); Konflux/Hermeto prefetch; Red Hat hermetic notebook images guidance (see `docs/references.md` §1, §3, §4)

## Context
v1 of the OpenCost Containerfile ran `git clone` and `go build` with network access inside the build. That has three problems:
- What gets built depends on the network at build time.
- The SBOM can't be trusted to list everything that went in.
- An attacker who controls a module proxy or a tag can change the build.

Iron Bank forbids internet calls inside the build. Konflux makes builds hermetic by prefetching with Hermeto.

## Decision
1. **Pin source by commit.** `image.yaml` carries `upstream.version` (tag) **and** `upstream.commit` (the SHA the tag dereferences to). CI clones the tag and **fails if `HEAD` ≠ `commit`**, which catches moved or re-pointed tags.
2. **Prefetch with Hermeto**, using the same tool Konflux uses, so ADR-007 is a lift-and-shift:
   `hermeto fetch-deps` (typed fetchers: `gomod`, `pip`, `npm`, `rpm`) → `generate-env` → `inject-files`.
   Image: `ghcr.io/hermetoproject/hermeto`, pinned by digest in the workflow (Hermeto is not on PyPI).
3. **Build with network off.** `docker build --network=none`. The source and `hermeto-output/` go into the build context; the Containerfile sources `/tmp/hermeto.env` before the toolchain runs.
4. **Typed fetchers only.** `generic` URL downloads need an ADR-level exception with sha256 pins (Red Hat's own rule).
5. **RPMs in the runtime stage.** `microdnf update` needs network, so the runtime stage takes base-image updates through **Renovate digest bumps** (ADR-004) instead of in-build updates. Adding RPMs later means Hermeto's `rpm` fetcher with an `rpms.lock.yaml`, not `microdnf install` from the internet.

## Consequences
- \+ Reproducible inputs; the dependency SBOM comes from Hermeto (ADR-008).
- \+ Same mechanics on GitHub Actions and Konflux.
- − Each language needs its lockfile (`go.sum`, `requirements*.txt`, `package-lock.json`). Upstreams without one can't be admitted until we generate and commit one, which counts as a patch to carry.
- − `ca-certificates` and other runtime RPM updates arrive only via base-digest bumps. These are frequent and automerged, so this is acceptable.

## Not doing
- Vendoring upstream source into this repo (a mirror maintenance burden; Iron Bank declares sources instead).
- GitHub archive tarballs + sha256. They are less robust than commit pins: archives are generated on demand and have changed checksums in the past. ⚠️ From experience, not re-verified.
