#!/usr/bin/env bash
# Claude Code PostToolUse hook (story DX.2). After an edit to a file that
# `make verify` checks, run it, so a change cannot be called done unverified.
# Does nothing for other files (docs).
#
# Receives the tool-use payload as JSON on stdin. On failure the output goes to
# stderr, which Claude Code feeds back to the agent.
# VERIFY_CMD overrides the command (used by tests/run.sh).
set -euo pipefail

payload="$(cat)"

# Extract the edited file path (portable; no jq dependency).
file="$(printf '%s' "$payload" |
  sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
  head -n1)"

case "$file" in
  */Containerfile | */Containerfile.ubi | */image.yaml | */vex.openvex.json | *.patch | \
    *.sh | */renovate.json | renovate.json | */Makefile | Makefile | \
    */.github/workflows/* | .github/workflows/* | */.hadolint.yaml | .hadolint.yaml | \
    */tests/fixtures/*)
    # Verify the tree the file lives in, which may be a git worktree and not
    # CLAUDE_PROJECT_DIR.
    repo="$(cd "$(dirname "$file")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
    cd "${repo:-${CLAUDE_PROJECT_DIR:-.}}"
    echo "verify-hook: '$file' changed, running '${VERIFY_CMD:-make verify}' in $PWD" >&2
    # shellcheck disable=SC2086 # VERIFY_CMD is a command line, split on purpose
    ${VERIFY_CMD:-make verify} >&2
    ;;
  *)
    : # not a checked file
    ;;
esac
