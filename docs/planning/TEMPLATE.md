# <Story code> — <short title>

<!--
The planning doc is a CONTEXT CAPSULE (docs/method.md): a cold session with no
memory and no conversation history must be able to execute this story from this
file alone, without re-scouting the repo. Fill every section; write "none"
rather than deleting one. An explicit "none" is information, an absent section
is a question. Delete this comment block in the real doc.
-->

Story: `docs/roadmap.md` <Story code> (status must be 👍 Approved before this
doc is implemented). Driver: <the need, audit finding or review comment that
prompted it, with ids or links>.

## Why (one paragraph)

<What breaks or is missing today, for whom, and why now.>

## Governing constraints

<The ADRs and CLAUDE.md invariants this change must respect, by number, with
one clause each on how they apply here. E.g. "ADR-003: the new build step must
not reach the network; any new dependency type needs a typed Hermeto fetcher.">

## Prior art

<The reference in `docs/references.md` this change copies. If there is none,
say so and state the risk (ADR-002 rule 7).>

## Design

<The change, with exact paths: which Containerfiles, `image.yaml` fields,
workflow jobs, scripts. New fields or steps shown as snippets. State explicitly
what is NOT changing.>

## Checks (red first)

<The failing checks to write BEFORE the change: the file, the level (static,
unit, image, end to end) and the behaviour each one pins, including the
negative cases. Where no automated check is possible, name the manual
verification and who runs it.>

## Human steps and outward-facing actions

<Anything an agent must not do: Partner Connect component creation, export
questionnaire, adding repo secrets, merging to `main` (which publishes). Say
who does each and what they hand back.>

## Out of scope

<What this story deliberately does not do, and where that work lives instead:
a follow-up story code, an ADR to write first, or an accepted limitation with
its consequence stated.>

## Done means

<Restate the roadmap Done line, plus anything mechanical: checks green, docs
updated (which ones), ⚠️ items resolved or still open, fix signature declared
if this is an audit fix.>
