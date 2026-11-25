# ADR-008: Supply-chain evidence: SBOM, signatures, provenance, CVE exceptions

- **Status:** Accepted. Revision 2, 2026-11-25. v1 is in `archive/`.
- **References:** Chainguard (SBOM + SLSA attestations on every image, signed with Sigstore); Iron Bank VAT (justified findings); Konflux/Hermeto dependency SBOMs (see `docs/references.md` §1, §4, §5)

## Decision
Every published artifact carries:
1. **SBOM** (SPDX JSON):
   - the Hermeto dependency SBOM (build inputs);
   - plus a syft scan of the final image (OS packages from UBI);
   - both attached as cosign attestations.
2. **Signature:** cosign keyless (GitHub OIDC), on the digest only, never the tag. The signing identity is the reusable workflow (ADR-006).
3. **Provenance:** `actions/attest-build-provenance`, generated inside the reusable workflow. The level we claim follows ADR-007.
4. **CVE gate at build time:** trivy fails on fixable **CRITICAL and HIGH**, the same severities the patch SLA covers (ADR-002 rule 4).
5. **Scheduled re-scan after publication:** every published digest that a consumer still references is re-scanned at least daily. A new fixable CRITICAL or HIGH opens an issue that starts the SLA clock. The re-scan does not fail anyone's build; it creates the work.
6. **Exceptions are OpenVEX**, in `images/<name>/vex.openvex.json`, not a trivy ignore file. Each statement needs a justification and an author. How long it lasts depends on what it says:
   - `not_affected` is a fact about one version of the code. It names the upstream version it applies to and is **re-validated on every upstream bump**. It does not expire by date; a monthly renewal of an unchanged fact becomes a rubber stamp.
   - `under_investigation`, and `affected` with an accepted risk, are temporary. They carry an **expiry ≤ 30 days** and CI fails when it passes.

   This is the Iron Bank VAT idea with a standard format.
7. **Verification docs:** the README shows customers the exact `cosign verify`, `cosign verify-attestation` and `gh attestation verify` commands with our workflow identity.

## Consequences
- \+ Evidence for CISO and tender questionnaires (ISO 27001 A.8.28/A.5.21, DORA ICT third-party, NIS2 supply chain) comes straight from the pipeline.
- \+ The gate, the re-scan and the SLA all use the same severities, so the SLA can be measured.
- − Gating on HIGH means more blocked PRs and more exceptions than gating on CRITICAL alone.
- − Exceptions need an owner, which is the factory team.

## Open questions
These decide whether the evidence is usable by the customers it is for. None is verified.
1. ⚠️ **Can a customer verify from the public pull spec?** We push and sign at `quay.io/redhat-isv-containers/<componentId>`; customers pull from Red Hat's catalog registry. Whether the signatures and attestations are reachable there is unknown. Story P.2 is not done until the README commands succeed against the public pull spec.
2. ⚠️ **Can an air-gapped customer verify?** Keyless verification needs Sigstore's transparency log and trust root, or an offline bundle and a distributed trust root. It also needs `oc-mirror` to carry signatures and attestations into the mirror. Air-gapped customers are our main audience, so story P.3 either demonstrates verification on a disconnected cluster or documents the limitation. **We do not promise air-gapped verification until then.**
3. ⚠️ Whether Red Hat's catalog shows attached cosign attestations for partner images. Don't promise customers that view until confirmed.
4. ⚠️ Whether trivy and other OpenVEX consumers accept the custom `x-stakater-*` fields we use for owner and expiry. If not, they move to a sidecar file next to the VEX document.
