# ADR-001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-25
- **References:** Michael Nygard, "Documenting Architecture Decisions" (2011); `adr-tools` creates this same record as `0001` in every new repo.

## Context
This repo is a long-lived factory that many products depend on (MTO, SCO, Reloader). We need decisions and their reasons to outlive the people who made them, and to be reviewed before code (design before code).

## Decision
- Every significant decision gets an ADR in `docs/adr/`, numbered per repo (`ADR-NNN-short-title.md`), Markdown only.
- Sections: Status, Date, **References** (the proven implementation we follow; see `docs/references.md`), Context, Decision, Consequences. Add "Not doing" or "Open questions" when useful.
- ADRs are accepted via PR review by CODEOWNERS before the implementing code merges.
- Never rewrite history. To change a decision, either:
  - **revise** it: copy the old version to `docs/adr/archive/<name>.vN.md` and bump the revision in the header (as with ADR-002); or
  - **supersede** it: set the old ADR's status to `Superseded by ADR-NNN`.
- Claims we haven't verified are marked ⚠️ until checked.

## Consequences
- \+ New engineers and auditors can read why the factory works the way it does.
- − Small overhead per decision; keep ADRs short (one page).
