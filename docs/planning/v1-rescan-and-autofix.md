# V.1 and V.2 — know about a vulnerability the day it is published, and open the fix

Stories: `docs/roadmap.md` V.1 and V.2 (👍 Approved 2026-11-27). Driver: the
owner's requirement to stay ahead on vulnerabilities, and ADR-002 rule 4,
which promises a patch SLA the pipeline cannot currently measure.

## Why (one paragraph)

Today a vulnerability in a published image is noticed only when someone
happens to rebuild it. Nobody learns of a vulnerability before it is
disclosed; what can be won is the time from disclosure to a patched, tested,
published image. That takes two things: looking every day at what is actually
published (V.1), and having the fix prepared by a machine so a person only has
to judge it (V.2). On 2026-11-27 the same two libraries were patched by hand
in three images; that is the work V.2 automates.

## Governing constraints

- **ADR-002 rule 4:** fixable CRITICAL in 7 days, HIGH in 30, clock starting
  when a fix is available. Published digests are re-scanned at least daily.
- **ADR-002 rule 2 and ADR-003 §6:** the only automatic change to upstream's
  source is a dependency bump for a vulnerability in the SLA, as a patch
  touching dependency files only, recorded under `deviations`.
- **ADR-002 rule 6:** a change to an image needs a factory-team review. V.2
  **opens** pull requests; it does not merge them.
- **ADR-008 §6:** an exception is an OpenVEX statement. The re-scan applies
  the image's VEX file, so an accepted finding is not reported again.
- **CLAUDE.md:** never weaken a check to get a green run.

## Prior art

- Chainguard and Iron Bank re-scan published images continuously
  (docs/references.md §1, §5).
- Renovate and Dependabot open dependency-bump pull requests. Neither can
  bump a dependency inside someone else's pinned source, which is our case.
- No reference for generating a deviation patch automatically. The procedure
  is the one in `.claude/skills/fix-cve`, made mechanical.

## Design

### V.1 Re-scan

`rescan.yaml`, daily and on demand, one job per image:

1. `latest-release.sh` picks the newest published tag for the image's current
   upstream version from GHCR. The digest on GHCR is the digest Red Hat has.
2. `rescan-image.sh` runs trivy against that reference with the same gate as
   the build (fixable CRITICAL and HIGH) and the image's VEX file.
3. `scan-findings.sh` reduces trivy's report to one line per finding, with a
   class: `os` (a UBI package), `gomod` (a Go module), `stdlib` (Go itself).
4. `report-findings.sh` keeps one GitHub issue per image: opened when the
   first finding appears (its creation date is the SLA clock), updated while
   findings change, closed when there are none.

### V.2 Automatic fix

When the re-scan has findings, `auto-fix.sh` prepares what it can:

| Class | Fix | Script |
|---|---|---|
| `os` | bump the UBI base digest to the current one | `bump-base.sh` |
| `gomod` | regenerate the image's dependency patch from pristine source, bumping exactly the modules named, to their fixed versions; update `deviations` | `fix-go-deps.sh` |
| `stdlib` | not automated: reported in the issue | — |

If that changes anything, the workflow pushes branch `auto/fix-<image>`, opens
a pull request, and starts the `verify` and `images` workflows on it. Those
build the patched image and run the smoke and functional tests, so the reviewer
sees whether the fix works before reading it.

The dependency patch is **regenerated, not appended**: one patch per image,
always derived from upstream's pristine source plus the full list of bumps. That
keeps it reviewable and means a superseded bump disappears by itself.

### What needs a repository setting

- "Allow GitHub Actions to create and approve pull requests" must be on, or
  the pull request is not opened. The branch is still pushed, and the issue
  says so.
- A pull request opened by the workflow's own token does not start pull-request
  workflows by itself. The workflow starts `verify` and `images` on the branch
  explicitly, which is why both gain a manual trigger.

## Checks (red first)

Unit, in `tests/run.sh`:

- **latest-release:** highest release of the current version; other versions
  and signature tags ignored; nothing published prints nothing.
- **scan-findings:** a trivy report fixture becomes the expected lines; classes
  are right; an empty report gives nothing.
- **fix-targets:** several findings for one module give its highest fixed
  version; `os` and `stdlib` findings are not targets.
- **report-findings**, against a stub `gh`: opens an issue when there is none,
  updates the open one, closes it when findings are gone, does nothing when
  there is nothing to do.
- **bump-base**, against a stub engine: rewrites `BASE_TAG` to the new digest;
  no change when it is already current.
- **update-deviations:** with the real `yq`, the `deviations` entry gets the
  union of fixed IDs and the bumps, and the rest of the file is untouched.

By hand, recorded in the PR: `fix-go-deps.sh` run against Dex's pristine source
with today's two bumps must reproduce the patch committed today.

## Human steps and outward-facing actions

- The repository setting above.
- Reviewing and merging the pull requests V.2 opens. A merge publishes.

## Out of scope

- Merging fixes automatically. That changes ADR-002 rule 6 and is the owner's
  decision; the functional tests are what would make it defensible.
- Go standard-library findings (a toolchain bump), reachability analysis, and
  the public SLA page: later stories.
- Languages other than Go.

## Done means

Every published image is re-scanned daily; a finding opens or updates one
issue per image and its absence closes it; for OS and Go-module findings a
pull request with the fix is opened and built; the docs and CLAUDE.md say how
it works; `make verify` green.
