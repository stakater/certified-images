# DX.2 — `make verify` runs the static and unit checks

Story: `docs/roadmap.md` DX.2 (👍 Approved 2026-11-25). Driver: the repo has no
checks at all, so "red → green" (docs/method.md) is impossible and story P.1
would be written with nothing to catch mistakes.

## Why (one paragraph)

Everything in this repo is configuration that fails late: a wrong regex in
`renovate.json` shows up weeks later as a missed bump, and a stale `ARG` in a
Containerfile shows up as a wrong version label on a certified image. One
command that checks all of it, run on every edit and on every PR, makes those
failures immediate. It also has to exist before P.1, because P.1 adds the
workflow and changes the Containerfile.

## Governing constraints

- **ADR-002 rule 7 (no invention):** use standard linters; write our own check
  only where no linter knows our rule.
- **ADR-003 / ADR-004 (pinned inputs):** the tools are build inputs too. Each
  runs from a container image pinned by `tag@digest`.
- **ADR-005:** `kind` is `container` or `xpkg`, nothing else.
- **ADR-003 §4:** `build.prefetch` uses typed fetchers; `generic` is rejected.
- **CLAUDE.md, "Claims match evidence":** a check that cannot run must fail
  loudly, never skip silently.

## Prior art

- hadolint, shellcheck, actionlint, `renovate-config-validator`: the standard
  tool for each file type.
- The edit hook is copied from `kube-ward/hack/verify-hook.sh` and its
  `.claude/settings.json` PostToolUse entry.
- No reference for the `image.yaml` rules: the schema is our own
  (docs/references.md, "Gaps"). Risk: the rules drift from what CI reads. P.1
  must read `image.yaml` through the same script.

## Design

New files:

| Path | What |
|---|---|
| `Makefile` | `verify` runs every target below; `ENGINE ?= docker` (podman works too); pinned tool images as variables |
| `scripts/check-image.sh <images/name>` | our own rules for one image directory (below) |
| `scripts/verify-hook.sh` | Claude Code PostToolUse hook: runs `make verify` after an edit to a checked file |
| `.claude/settings.json` | registers the hook |
| `.hadolint.yaml` | hadolint config; every ignored rule has a comment saying why |
| `tests/run.sh` | plain-bash test runner, no framework |
| `tests/fixtures/` | good and deliberately broken inputs |
| `.github/workflows/verify.yaml` | runs `make verify` on pull requests; actions pinned by commit SHA; no secrets, no publish |

`make` targets:

| Target | Checks | Tool |
|---|---|---|
| `lint-containerfiles` | `images/*/Containerfile` | hadolint |
| `lint-shell` | `scripts/*.sh`, `tests/*.sh` | shellcheck |
| `lint-workflows` | `.github/workflows/*` | actionlint |
| `check-renovate` | `renovate.json` | `renovate-config-validator --strict` |
| `check-images` | every `images/*/` | `scripts/check-image.sh` |
| `test` | script tests and the self-test of every check above | `tests/run.sh` |

`scripts/check-image.sh` rules (YAML is read with a pinned `yq` image, then `jq`):

1. `kind` is `container` or `xpkg`.
2. `name` equals the directory name.
3. `upstream.repo` is an `https://` URL; `upstream.version` is set;
   `upstream.commit` is 40 hex characters.
4. `upstream.license` is set and is not `TODO`.
5. The `# renovate: datasource=… depName=…` comment sits directly above
   `version:`, with `commit:` on the next line. Renovate's regex manager needs
   exactly this shape, and nothing else would notice if it broke.
6. `build.prefetch` is valid JSON, and no fetcher has `type: generic`.
7. `redhat.secretSuffix` matches `[A-Z0-9_]+`.
8. **No drift between `image.yaml` and the Containerfile:** the `ARG` defaults
   `UPSTREAM_VERSION`, `UPSTREAM_COMMIT` and `GO_VERSION` equal
   `upstream.version`, `upstream.commit` and `build.goVersion`. Renovate bumps
   only `image.yaml`, so without this check the labels and the Go version go
   stale without anyone noticing.
9. The Containerfile declares `BASE_REGISTRY`, `BASE_IMAGE` and `BASE_TAG`.

A JSON Schema file was considered and not used: there is no pinned,
container-packaged validator that reads YAML, and rules 5 and 8 cannot be
expressed in a schema anyway.

Not changing: `images/opencost/*` content (except what a linter proves wrong),
`scripts/new-image.sh` behaviour, the ADRs.

## Checks (red first)

All in `tests/run.sh`, written and seen failing before the Makefile and
`check-image.sh` exist.

- **Self-test, one per check:** each target's tool is run against a broken
  fixture and must exit non-zero: a Containerfile hadolint rejects, a shell
  script shellcheck rejects, a workflow actionlint rejects, an invalid
  `renovate.json`.
- **`check-image.sh`, table-driven:** the good fixture passes; one broken
  fixture per rule 1–9 fails, and the error names the rule.
- **`new-image.sh`:** with a stub `git` on `PATH` (no network), it writes an
  `image.yaml` carrying the dereferenced commit of an annotated tag, falls back
  to the tag's own SHA for a lightweight tag, refuses an existing directory,
  fails on an unknown tag, and its output fails `check-image.sh` on exactly two
  rules, on purpose: rule 4 (the scaffold writes `license: TODO`) and rule 8
  (it writes `goVersion: "TODO"`). A person has to fill in both.
- **Hook:** given a payload naming `images/x/Containerfile` it runs verify;
  given `docs/x.md` it does nothing.

## Human steps and outward-facing actions

None. `verify.yaml` only reads the repo. Pushing the branch and opening the PR
are done on request.

## Out of scope

- The build pipeline, and any check that needs a built image (structure tests,
  preflight): story P.1.
- **A check that base and toolchain images are digest-pinned (ADR-004).** It
  would fail today on the OpenCost Containerfile. P.1 pins the images and adds
  that rule to `check-image.sh` in the same change.
- VEX expiry and patch-scope checks (ADR-008 §6, ADR-003 §6): added with the
  first VEX file or patch, or in P.1 if the workflow needs them.
- `redhat.componentId` may still be a `TODO` placeholder here; the publish job
  in P.2 must refuse it.

## Done means

`make verify` is green on the branch and runs hadolint, shellcheck, actionlint,
`renovate-config-validator` and `check-image.sh`, plus `tests/run.sh`; every
check is shown to fail on a broken fixture; the edit hook is registered;
`verify.yaml` runs it on PRs; `CLAUDE.md` "Status" and "Testing", and the
method.md enforcement table, say what is now enforced; the roadmap marks DX.2
✅ with a link to this file.
