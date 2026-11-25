# ADR-007: Build platform: GitHub Actions, with Konflux re-evaluated on triggers

- **Status:** Accepted. Revision 2, 2026-11-25. v1 is in `archive/`.
- **References:** Konflux (Tekton, Tekton Chains, Hermeto, Conforma, Quay); Red Hat Trusted Software Factory; GitHub, "Using artifact attestations and reusable workflows to achieve SLSA v1 Build Level 3" (see `docs/references.md` §3)

## Context
We need certified OpenCost quickly, and no platform work should block it. Longer term we want strong provenance and policy-gated releases. Red Hat uses Konflux for this, and running Konflux on Stakater Cloud would support our sovereign supply-chain pitch. It would also be a platform we have to operate.

v1 of this ADR said GitHub Actions reaches SLSA Build L2 at best and made "a customer asks for L3" a trigger to migrate. That was wrong: GitHub documents a route to Build L3 using artifact attestations generated inside a reusable workflow (checked 2026-11-25). ADR-006 already makes the pipeline a reusable workflow.

## Decision
- **Build on GitHub Actions** (`.github/workflows/build-certify.yaml`, a reusable workflow per ADR-006). Keep the steps Konflux-shaped so a later move is a re-host, not a redesign:
  - Hermeto prefetch (ADR-003);
  - offline build;
  - SBOM;
  - CVE gate;
  - preflight;
  - push;
  - cosign sign + attest (ADR-008).
- **Provenance claim.** We state the level we have checked, and no higher. Until we have assessed our setup against the SLSA v1 Build L3 requirements and recorded the result, the claim is L2.
- **Konflux is re-evaluated, not scheduled.** When any trigger below fires, we write a new ADR that decides whether to move. A trigger does not commit us to migrate.
  - ≥ 10 admitted images; **or**
  - a customer or tender requires something GitHub Actions cannot give: a build platform we host ourselves, or Conforma-style policy gates on release; **or**
  - the first SCO xpkg family is admitted.
- **Portability test**, to be kept true now: `image.yaml` and Containerfiles contain nothing GitHub-specific. Only CI definitions would move.

## Consequences
- \+ No platform work blocks the OpenCost pilot.
- \+ The strongest reason to run Konflux is now sovereignty and policy gating, not a SLSA level. That is a business decision, which is why it gets its own ADR when a trigger fires.
- − A hosted GitHub runner is not a build platform we control. Customers who need that are not served until Konflux or an equivalent.

## Not doing
- Building our own Tekton pipelines from scratch: Konflux already packages them.
- Self-hosted GitHub runners. They weaken the isolation the provenance claim rests on.
