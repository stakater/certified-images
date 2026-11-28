# P.1b — an image with a web UI built with pnpm can be built

Story: `docs/roadmap.md` P.1b (👍 Approved 2026-11-28 by the owner, in
conversation: "now add prometheus to the factory", after being told the UI
needed a story). Driver: MTO needs Prometheus, and Red Hat's hardened image of
it failed our CVE gate (ADR-002 rule 1, rev 10).

## Why (one paragraph)

Prometheus is a Go program with a web UI written in TypeScript, built with
pnpm and compiled into the binary (build tag `builtinassets`). Every image so
far was Go only: one toolchain image, one `gomod` prefetch. Without the UI
build the binary has no UI; taking upstream's prebuilt `prometheus-web-ui`
tarball would be shipping an artifact we did not build, through a `generic`
download the rules forbid.

## Governing constraints

- ADR-002 rule 2: build from source; never re-ship upstream's built artifacts.
- ADR-003 decision 3: every build stage runs with the network off.
- ADR-003 decision 4 and `check-image` rule 6: typed fetchers only.
- ADR-003 decision 8 (revision 4, added with this story): the rule for stages
  in another language.
- ADR-004 and `check-image` rule 10: every external image pinned by digest.
- CLAUDE.md "No invention": Hermeto's pnpm fetcher is the reference.

## Prior art

Hermeto's `pnpm` package manager (`docs/references.md` §4, Hermeto): it
downloads the packages a `pnpm-lock.yaml` names, verifies their integrity,
rewrites the lockfile's tarball entries to local files and writes a registry
setting into `.npmrc`. Upstream's own build steps are in its `Makefile`
(`ui-install`, `ui-build`, `assets-compress`) and `scripts/compress_assets.sh`.

## Design

No pipeline script changes. Everything is in the image directory, plus two
Renovate rules.

- `images/prometheus/image.yaml`: `build.prefetch` is an array: `gomod` at `.`,
  `pnpm` at `web/ui`, `pnpm` at `web/ui/react-app` (upstream keeps the older
  React app outside the workspace, with its own lockfile).
- `images/prometheus/Containerfile`, three build stages:
  1. `pnpm`: `ghcr.io/pnpm/pnpm:11.29.0@sha256:…`, only as the source of the
     pnpm program (`/opt/pnpm`).
  2. `ui`: `docker.io/library/node:24.21.0-bookworm@sha256:…` (Node 24 per
     upstream's `.nvmrc`; the full image, because pnpm 11 needs `libatomic`,
     which `-slim` lacks). Runs upstream's steps: install both lockfiles with
     `--frozen-lockfile`, `pnpm run build`, `scripts/compress_assets.sh`.
  3. `build`: the Go stage as in every image, with the compressed assets and
     the generated `embed.go` copied in, and `-tags netgo,builtinassets`.
- `renovate.json`: pnpm is held below 12; Node major bumps are disabled (a
  person bumps Node with the upstream release).
- NOT changing: `scripts/prefetch.sh`, `build-image.sh`, `check-image.sh`.
  Rule 6 already accepts an array of typed fetchers; rule 10 already checks
  every `FROM`.

## Checks (red first)

- Seen to fail first, by hand, 2026-11-28, each with the network off:
  `pnpm install --offline` (pnpm's own offline mode does not use Hermeto's
  layout); pnpm 12.24.0 (`relative URL without a base`); pnpm 11 on
  `node:…-slim` (`libatomic.so.1` missing). The combination in the design is
  the one that then built both UIs and ran `compress_assets.sh`.
- Static: `make verify` (hadolint, rule 6, rule 10, Renovate config).
- Image and end to end: the pull request's CI run, which is the first full
  build: prefetch of three inputs, offline UI and Go build, image test.
- Functional (`images/prometheus/functional/test.sh`): besides scraping and
  answering a query, it fetches the UI page and one of its scripts. That is
  the check that the UI built here is inside the binary.

## Human steps and outward-facing actions

Merging publishes to GHCR; a person authorises it. Partner Connect component,
export questionnaire and registry key, as for any image.

## Out of scope

- The licence texts of the JavaScript packages bundled into the UI. Upstream
  ships them in its release tarball (`npm_licenses.tar.bz2`), not in its image.
  ⚠️ To settle before the image is submitted to Red Hat.
- A scaffold template for images with a UI stage; one image does not make a
  pattern.
- Other JavaScript package managers.

## Done means

Prometheus builds in CI from source, UI included, with the network off;
`make verify` is green; ADR-003 revision 4 is in place with revision 3
archived; the roadmap, README and the add-image skill mention the case.
