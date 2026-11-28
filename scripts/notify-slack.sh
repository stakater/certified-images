#!/usr/bin/env bash
# Tell a Slack channel that an image was published (story N.1):
#   scripts/notify-slack.sh [--print] <image> <tag> <repository@sha256:digest>
#
# Posts to the incoming webhook in SLACK_WEBHOOK_URL. The address is a secret:
# whoever has it can post to the channel. It is given to curl on stdin, never
# on its command line, and never printed.
#
# --print writes the message that would be sent and sends nothing.
# Exit 3: no webhook is configured, so nothing was sent. The caller decides
# whether that matters; for a publish it must not fail the release.
set -euo pipefail

SITE=${NOTIFY_SITE:-https://stakater.github.io/certified-images}
print=false
if [ "${1:-}" = "--print" ]; then
  print=true
  shift
fi
IMAGE=${1:?usage: notify-slack.sh [--print] <image> <tag> <repository@sha256:digest>}
TAG=${2:?usage: notify-slack.sh [--print] <image> <tag> <repository@sha256:digest>}
REF=${3:?usage: notify-slack.sh [--print] <image> <tag> <repository@sha256:digest>}
[[ "$IMAGE" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
  echo "notify-slack: '$IMAGE' is not an image name" >&2
  exit 1
}
[[ "$REF" =~ @sha256:[a-f0-9]{64}$ ]] || {
  echo "notify-slack: the reference must be by digest (repository@sha256:...), got '$REF'" >&2
  exit 1
}

run=""
if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
  run="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi
payload=$(jq -cn --arg image "$IMAGE" --arg tag "$TAG" --arg ref "$REF" --arg page "$SITE/image.html?name=$IMAGE" --arg run "$run" '
  { text: ("Published *" + $image + "* `" + $tag + "`\n`" + $ref + "`\n<" + $page + "|What was checked, and how to verify it>"
           + (if $run == "" then "" else " · <" + $run + "|pipeline run>" end)) }')

if [ "$print" = true ]; then
  printf '%s\n' "$payload"
  exit 0
fi

URL=$(printf '%s' "${SLACK_WEBHOOK_URL:-}" | tr -d '[:space:]')
if [ -z "$URL" ]; then
  echo "notify-slack: not sent. No webhook is configured: a repository admin adds the secret SLACK_WEBHOOK_URL (docs/setup.md)." >&2
  exit 3
fi
case "$URL" in
  https://hooks.slack.com/*) ;;
  *)
    echo "notify-slack: SLACK_WEBHOOK_URL is not a Slack incoming webhook address (https://hooks.slack.com/...). Nothing was sent." >&2
    exit 1
    ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '%s' "$payload" >"$work/payload.json"
code=$(printf 'url = "%s"\n' "$URL" |
  curl --config - -s --max-time 30 -o "$work/answer" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data "@$work/payload.json" || true)
if [ "$code" != "200" ]; then
  echo "notify-slack: Slack answered HTTP ${code:-none}. The message was not delivered." >&2
  exit 1
fi
echo "notify-slack: told Slack that $IMAGE $TAG was published"
