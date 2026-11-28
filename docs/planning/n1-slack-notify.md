# N.1 — the team is told when an image is published

Story: `docs/roadmap.md` N.1 (👍 Approved by the owner: asked for on 2026-11-28,
"a notification on slack channel whenever we detect new version and build it",
and "merge and proceed" after the catalogue site). Driver: product teams consume
images by digest and nothing tells them a new one exists.

## Why (one paragraph)

A new release changes the digest a product should use. Today a product team
finds out by looking. The catalogue site shows the current state; a message in
a channel says that it changed.

## Governing constraints

- CLAUDE.md "Secrets by reference only": the webhook address is a secret. It
  is read from the environment, given to curl on stdin, never on a command
  line, never printed.
- CLAUDE.md "No secret is named per image": one secret, `SLACK_WEBHOOK_URL`,
  for the repository.
- CLAUDE.md "One step, one script".
- A notification is not a gate: it must never fail or block a release.

## Prior art

`scripts/rh-component-info.sh` and `scripts/pyxis-probe.sh`: a secret passed to
curl through `--config -`, and tests that look for it on the command line and
in the output. `scripts/rh-registry-login.sh`: exit status 3 for "not
configured, skipped".

## Design

- `scripts/notify-slack.sh [--print] <image> <tag> <repository@sha256:digest>`
  posts one message to the Slack incoming webhook in `SLACK_WEBHOOK_URL`: the
  image, the release, the reference by digest, a link to the image's page on
  the catalogue site and, in CI, to the pipeline run. `--print` shows the
  message and sends nothing. Exit 3 when no webhook is configured.
- `.github/workflows/build-certify.yaml`: a "Notify Slack" step after the image
  is pushed, signed and attested, so only a complete release is announced. A
  missing webhook is a notice in the run; a failed post is a warning. Neither
  fails the release.
- "A new upstream version was detected" needs no code: Renovate opens a pull
  request labelled `upstream-bump`, and the GitHub app for Slack can post those
  to a channel (`docs/setup.md`). ⚠️ Renovate has not opened a pull request on
  this repository yet.
- NOT changing: what is published, or when.

## Checks (red first)

`tests/run.sh`, with the stub curl: it posts on 200; the webhook address is not
on curl's command line and is never printed, including when refused; any other
answer fails; an address that is not a Slack webhook is refused; no webhook
exits 3 and names the secret; the message names the image, release and digest
reference and links the image's page; a reference by tag is refused.

## Human steps and outward-facing actions

- A Slack admin creates an incoming webhook for the channel; a repository admin
  adds it as the secret `SLACK_WEBHOOK_URL`. An agent does neither.
- Optional: subscribe the channel to `upstream-bump` pull requests with the
  GitHub app for Slack.
- Posting to Slack is outward-facing; it happens only from the publish
  workflow, on a merge to `main`.

## Out of scope

- Messages for failed publishes or for the daily re-scan's findings.
- Per-product channels.

## Done means

The script and its tests are in `make verify`; the publish workflow calls it;
`docs/setup.md` says what a person must set up; the first publish after the
secret exists posts a message. Until the secret exists the step says so and the
release is unaffected.
