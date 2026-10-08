#!/usr/bin/env sh
# Smoke test: build the image, start it, and check that Gatus comes up healthy
# with every endpoint from config/config.yaml loaded.
#
# Usage: test/smoke.sh            (podman if available, otherwise docker)
#        CONTAINER_CLI=docker test/smoke.sh
set -eu

cd "$(dirname "$0")/.."

if [ -z "${CONTAINER_CLI:-}" ]; then
  if command -v podman >/dev/null 2>&1; then CONTAINER_CLI=podman; else CONTAINER_CLI=docker; fi
fi
IMAGE=moza-gatus-smoke
CONTAINER=moza-gatus-smoke
PORT="${SMOKE_PORT:-18080}"
BASE_URL="http://127.0.0.1:${PORT}"

EXPECTED_ENDPOINTS='mijnoverheid
mijnoverheid www
mijnoverheid docs
mijnoverheid profiel service (acceptatie)
mijnoverheid moza
cert-warning
cert-critical
moza
cert'

cleanup() {
  "$CONTAINER_CLI" rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
cleanup

fail() {
  echo "FAIL: $*" >&2
  echo "--- container log ---" >&2
  "$CONTAINER_CLI" logs "$CONTAINER" >&2 2>&1 || true
  exit 1
}

echo "building image with $CONTAINER_CLI"
"$CONTAINER_CLI" build -q -t "$IMAGE" . >/dev/null

echo "starting container on port $PORT"
"$CONTAINER_CLI" run -d --name "$CONTAINER" \
  -e MATTERMOST_WEBHOOK_URL=http://127.0.0.1:9/smoke-test \
  -p "127.0.0.1:${PORT}:8080" "$IMAGE" >/dev/null

echo "waiting for $BASE_URL/health"
i=0
until curl -fsS "$BASE_URL/health" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 30 ] || sleep 1
  [ "$i" -lt 30 ] || fail "Gatus did not become healthy within 30s"
done

echo "checking that the Mattermost alerting provider picked up MATTERMOST_WEBHOOK_URL"
"$CONTAINER_CLI" logs "$CONTAINER" 2>&1 | grep -q 'configuredProviders=\[mattermost\]' \
  || fail "Mattermost provider not configured; env substitution in config.yaml broken?"

echo "waiting for all endpoints in $BASE_URL/api/v1/endpoints/statuses"
i=0
while :; do
  statuses="$(curl -fsS "$BASE_URL/api/v1/endpoints/statuses" 2>/dev/null || true)"
  missing=""
  while IFS= read -r name; do
    case "$statuses" in
      *"\"name\":\"$name\""*) ;;
      *) missing="$missing
  - $name" ;;
    esac
  done <<EOF
$EXPECTED_ENDPOINTS
EOF
  [ -n "$missing" ] || break
  i=$((i + 1))
  [ "$i" -lt 60 ] || fail "endpoints missing after 60s:$missing"
  sleep 1
done

echo "OK: Gatus is healthy and all $(printf '%s\n' "$EXPECTED_ENDPOINTS" | wc -l | tr -d ' ') endpoints are loaded"
