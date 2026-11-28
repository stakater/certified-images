# P.1a — an upstream that vendors its dependencies can be built

Story: `docs/roadmap.md` P.1a (👍 Approved 2026-11-28 by the owner, in
conversation: "go, drop the vendored copy and build both operands"). Driver:
etcd-druid (PR #32) cannot be used by a certified product without the two
images its etcd pods run, `etcd-wrapper` and `etcd-backup-restore`, and neither
can be prefetched today.

## Why (one paragraph)

Both operand repositories commit a `vendor/` directory. Hermeto regenerates it
with `go mod vendor` and rejects the source in strict mode if anything differs.
For both, something does: upstream gitignores files inside `vendor/`
(`CLAUDE.md`, a `.swp` file), so the regenerated directory has files the
committed one lacks. Tried locally on 2026-11-28 with `scripts/prefetch.sh`:
`vendor changed: A vendor/go.opentelemetry.io/otel/CLAUDE.md` for both, plus
`A vendor/github.com/santhosh-tekuri/jsonschema/v6/.swp` for
etcd-backup-restore; no modified or deleted file. SCO needs these images now.

## Governing constraints

- ADR-003 decision 2 and 4: dependencies are prefetched with Hermeto, typed
  fetchers only. Unchanged: the `gomod` fetcher is still used.
- ADR-003 decision 6: patches may touch dependency manifests and lockfiles
  only. Unchanged: dropping `vendor/` is not a patch and is not expressed as one.
- ADR-003 decision 7 (revision 3, added with this story): the rule itself.
- ADR-002 rule 2: build from source at a pinned commit. The compiled first-party
  source is still upstream's at the pinned commit.
- ADR-002 rule 7 (no invention): there is no reference for dropping the
  directory; ADR-003 names that as a risk.
- CLAUDE.md "Do not weaken a check": Hermeto's permissive mode is rejected for
  that reason.
- CLAUDE.md "A check that cannot run must fail": a declared `dropVendor` with
  nothing to drop fails.

## Prior art

Hermeto's vendoring check (`docs/references.md` §4, Konflux prefetching docs)
is the check we keep in strict mode. Dropping the directory has no reference;
the risk is in ADR-003's Consequences.

## Design

- `image.yaml`: optional `build.dropVendor: true`.
- `scripts/fetch-source.sh`: after the patches are applied, if
  `build.dropVendor` is `true`: fail unless `<out>/vendor/modules.txt` exists;
  remove `<out>/vendor`; print `fetch-source: dropped upstream's vendor/`.
  Nothing else in the tree is touched.
- `scripts/check-image.sh`, new rule 18: `build.dropVendor`, when present, is
  the boolean `true` or `false`.
- Containerfiles of such images build without `-mod vendor`; with no `vendor/`
  Go reads the Hermeto module cache, as in every other image.
- NOT changing: `scripts/prefetch.sh`, the Hermeto invocation and its mode, the
  patch rules, `scripts/fix-go-deps.sh` (it calls `fetch-source.sh` and so gets
  a tree without `vendor/`, which is what `go get` needs).

## Checks (red first)

In `tests/run.sh`, unit level, against the throwaway local upstream, extended
with a tag whose tree has `vendor/modules.txt`:

- `fetch-source`: with `build.dropVendor: true`, `vendor/` is gone and
  `go.mod` and `main.go` are still there.
- `fetch-source`: without it, `vendor/` is kept (existing behaviour).
- `fetch-source`: `dropVendor: true` on a tree with no `vendor/modules.txt`
  fails, naming `vendor`.
- `check-image`: `build.dropVendor: yes-please` fails rule 18; `true` passes.

Image and end-to-end level: the pull request's CI run for `etcd-wrapper` and
`etcd-backup-restore` (prefetch, offline build, tests, CVE gate, preflight).

## Human steps and outward-facing actions

None for the pipeline change. For the two images: Partner Connect components,
export questionnaires and registry keys, by a person, as for any image. Merging
publishes; a person merges.

## Out of scope

- The `alpine` init image etcd-druid uses for a local backup store: it runs as
  root and is not needed without a local store. Not built.
- The older operand pair (`etcd-wrapper` v0.6.2, `etcdbrctl` v0.41.2) used when
  the `UpgradeEtcdVersion` feature gate is off. Not built.
- Making etcd-druid default to our operand images: a product sets them per
  `Etcd` or through the operator's image override file.

## Done means

An image may declare `build.dropVendor: true`; the four checks above exist and
were seen to fail before the change; `make verify` is green; ADR-003 revision 3
is in place with revision 2 archived; `etcd-wrapper` and `etcd-backup-restore`
build in CI through the unchanged, strict prefetch; CLAUDE.md and README layout
mention the field.
