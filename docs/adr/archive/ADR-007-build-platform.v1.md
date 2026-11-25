# ADR-007: Build platform: GitHub Actions now, Konflux as the target

- **Status:** Accepted
- **Date:** 2026-11-25
- **References:** Konflux (Tekton, Tekton Chains, Hermeto, Conforma, Quay; SLSA Build L3); Red Hat Trusted Software Factory (see `docs/references.md` §3)

## Context
We need certified OpenCost within hours, not weeks. Long term, we want SLSA L3 provenance and policy-gated releases, which is what Red Hat itself uses Konflux for. Running Konflux on Stakater Cloud would also support our sovereign supply-chain pitch.

## Decision
- **Now:** GitHub Actions (`.github/workflows/build-certify.yaml`). Keep the steps Konflux-shaped so the move is a re-host, not a redesign:
  - Hermeto prefetch (ADR-003);
  - offline build;
  - SBOM;
  - CVE gate;
  - preflight;
  - push;
  - cosign sign + attest (ADR-008).
- **Migrate to Konflux** (self-hosted on Stakater Cloud) when **any** of these triggers fires:
  - ≥ 10 admitted images, **or**
  - a customer or tender asks for SLSA L3, **or**
  - the first SCO xpkg family goes in.
- Migration test: same `image.yaml` and Containerfiles, unchanged; only CI definitions move to `.tekton/`.

## Consequences
- \+ No platform work blocks the OpenCost pilot.
- − GitHub Actions gives SLSA Build L2 at best (hosted runner, signed provenance via `actions/attest-build-provenance`). Don't claim L3 until Konflux.

## Not doing
- Building our own Tekton pipelines from scratch: Konflux already packages them.
