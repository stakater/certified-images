# S.1 — a public catalogue of the images

Story: `docs/roadmap.md` S.1 (👍 Approved 2026-11-28 by the owner, in
conversation: "make it public, show ghcr address, and build it"). Driver: the
owner's request for a browsable site like Red Hat's and Chainguard's, with a
detailed page per image. Design: https://claude.ai/artifact/SMs1bEL2DsphtKsgorYnHp
(private to the owner).

## Why (one paragraph)

The factory's output is ten public images with evidence, and the only way to
see them is to read this repository. Product teams cannot see at a glance which
release to use, and customers on AKS or EKS, who can pull our public images
without a Red Hat login, have nowhere to find them. Red Hat and Chainguard show
their images on a site; ours can show something they do not lead with: what
each release was put through, what was not checked, and commands to re-check it.

## Governing constraints

- ADR-002 rev 12 (added with this story): a public image's GHCR address may be
  given to customers by digest; "certified" only if Red Hat lists it.
- ADR-002, visibility: an image not declared public must not appear.
- CLAUDE.md invariant 8, "Claims match evidence": every statement on the site
  comes from the repository, the registry, GitHub's attestation service or
  Red Hat's catalogue at generation time. Where a source cannot be read, the
  site says "unknown", never the favourable answer.
- CLAUDE.md "Never say an image works on OpenShift": the site carries that
  statement on every image page.
- CLAUDE.md "One step, one script", bash 3.2 and 5, tools pinned in `tools.env`.
- Secrets: none. The workflow uses its own token, read-only except for Pages.

## Prior art

Red Hat Hardened Images (images.redhat.com): a list by category; per image,
container details, a quick-start pull command, current CVE results, SBOM,
image verification and a searchable list of tags with digests. Chainguard's
image directory. The repository's own `publish-plan.sh` / `list-tags.sh` for
reading the registry.

## Design

No server and no build toolchain. A script writes one JSON file; static pages
render it in the browser.

- `scripts/site-data.sh <out-dir>` writes `<out-dir>/catalog.json`:
  - per image declared public: name, display name, summary, description, tags,
    upstream repository, version and commit, licence, consumers, deviations
    (reason, fixes, bumps, upstream PR), base image and digest, toolchain, the
    kind of smoke test, the functional test's own description, the stacks it
    is in;
  - from the registry (`scripts/list-tags.sh`, crane): its releases and each
    one's digest;
  - from GitHub (`gh attestation verify`): per release, whether build
    provenance verifies. An unsigned release shows as such;
  - from GitHub issues: the open "Vulnerabilities in <image>" issue of the
    daily re-scan, if any;
  - from Red Hat's public catalogue API: for an image with a component ID,
    whether `registry.connect.redhat.com/stakater/<name>` is published.
    Unreachable or absent means "not listed" or "unknown", never "certified";
  - from the newest release itself, with the pinned tools (added 2026-11-28,
    after the owner asked for more detail, with Red Hat's image pages as the
    model): its container configuration and size (crane); whether its signature
    verifies and its two signed SBOMs, verified and unpacked (cosign, now
    pinned in `tools.env`); and a scan of every severity (trivy). These go to
    `details/<name>.json` and `sbom/<name>.<kind>.spdx.json`. The scan shown is
    wider than the build gate, which refuses fixable critical and high only:
    the site shows every finding, fixable or not, and says which is which.
  - `site/external.json`, kept by hand: images used from Red Hat, with how far
    we could check them.
  - `SITE_OFFLINE=1` skips every network source (releases empty, statuses
    "unknown"); the unit tests use it.
- `site/index.html`, `site/image.html`, `site/app.js`, `site/style.css`: the
  catalogue and one page per image (`image.html?name=<name>`), with a header
  (architecture, stream, size, last built, and a card with the scan result)
  and tabs: Overview, Container details, Tags, SBOM (searchable, with the SPDX
  files to download), Verify build, CVEs.
- `make site` writes `_site/` (data plus pages), viewable by opening the file
  through any static server.
- `.github/workflows/site.yaml`: builds on pull requests (uploaded as an
  artifact, not deployed); builds and deploys to GitHub Pages on a push to
  `main` that touches images, stacks, the site or its script, after every
  `publish` run, daily after the re-scan, and by hand.
- NOT changing: the image pipeline. The site reads; it publishes no image and
  gates nothing.

## Checks (red first)

`tests/run.sh`, unit level, with `SITE_OFFLINE=1` and fixture image directories:

- the output is valid JSON with one entry per public image;
- an image not declared public is **absent**;
- upstream pin, licence, consumers and deviations are carried over exactly;
- an image with the placeholder component ID has Red Hat status
  "not submitted"; with a real ID and no network, "unknown", not "certified";
- offline, releases are empty and nothing is marked verified;
- offline, an image's scan, SBOM and signature are "unknown" with no counts and
  no package list: an unread scan must never look like a clean one;
- a malformed `image.yaml` fails the script; it does not skip the image.
- The pages are static; `make verify` lints the workflow and the script. The
  pages themselves are checked by hand against the generated data, stated in
  the pull request.

## Human steps and outward-facing actions

- GitHub Pages must be enabled for the repository with "GitHub Actions" as the
  source. Enabling it and the first deploy make the site public: authorised by
  the owner on 2026-11-28.
- A custom domain, if wanted, is the owner's to set up.

## Out of scope

- Scan results for releases other than the newest.
- Search across images, RSS, a "request an image" form.
- Slack notifications (separate backlog item).

## Done means

The site is live on GitHub Pages; it lists exactly the images declared public;
each image page shows its GHCR address by digest, releases with their digests
and whether provenance verifies, deviations, checks, what was not checked, and
verify commands; the unit checks are in `make verify`; ADR-002 rev 12, the
vision page, CLAUDE.md and the README are updated.
