# ADR-008: Supply-chain evidence: SBOM, signatures, provenance, CVE exceptions

- **Status:** Accepted
- **Date:** 2026-11-25
- **References:** Chainguard (SBOM + SLSA attestations on every image, signed with Sigstore); Iron Bank VAT (justified findings); Konflux/Hermeto dependency SBOMs (see `docs/references.md` §1, §4, §5)

## Decision
Every published artifact carries:
1. **SBOM** (SPDX JSON):
   - the Hermeto dependency SBOM (build inputs);
   - plus a syft scan of the final image (OS packages from UBI);
   - both attached as cosign attestations.
2. **Signature:** cosign keyless (GitHub OIDC), on the digest only, never the tag.
3. **Provenance:** `actions/attest-build-provenance` now (SLSA L2); Tekton Chains after ADR-007 (L3).
4. **CVE gate:** trivy fails on fixable CRITICAL. Anything that can't be fixed in time goes in `images/<name>/vex.openvex.json` (OpenVEX), not a trivy ignore file. Each statement needs:
   - a justification;
   - an author;
   - an **expiry ≤ 30 days**.

   CI fails on expired statements. This is the Iron Bank VAT idea with a standard format.
5. **Verification docs:** the README shows customers the exact `cosign verify` / `cosign verify-attestation` commands with our OIDC identity regex.

## Consequences
- \+ Evidence for CISO and tender questionnaires (ISO 27001 A.8.28/A.5.21, DORA ICT third-party, NIS2 supply chain) comes straight from the pipeline.
- − Exceptions expire on purpose. Someone has to own them, which is the factory team.

⚠️ Verify at implementation: whether Red Hat's catalog shows attached cosign attestations for partner images. Don't promise customers that view until confirmed.
