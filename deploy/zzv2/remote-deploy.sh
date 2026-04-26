#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/work/project/zzv2}"
APP_IMAGE="${APP_IMAGE:-sub2api-zzv2}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

set_env_value() {
  key="$1"
  value="$2"
  tmp_file="$(mktemp)"
  if [ -f .env ]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { found = 0 }
      $0 ~ "^" key "=" {
        print key "=" value
        found = 1
        next
      }
      { print }
      END {
        if (!found) {
          print key "=" value
        }
      }
    ' .env > "$tmp_file"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp_file"
  fi
  cat "$tmp_file" > .env
  rm -f "$tmp_file"
}

cd "${DEPLOY_DIR}"

mkdir -p data

if [ ! -f .env ]; then
  echo ".env is missing in ${DEPLOY_DIR}; create it on the server before deploying." >&2
  exit 1
fi

if [ "${IMAGE_TAG#*:}" != "${IMAGE_TAG}" ]; then
  APP_IMAGE="${IMAGE_TAG%:*}"
  IMAGE_TAG="${IMAGE_TAG##*:}"
fi

set_env_value IMAGE_TAG "${IMAGE_TAG}"
set_env_value APP_IMAGE "${APP_IMAGE}"

if [ -n "${GHCR_TOKEN:-}" ]; then
  printf '%s' "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME:-github-actions}" --password-stdin
fi

for attempt in 1 2 3 4 5; do
  if docker compose --env-file .env -f "${COMPOSE_FILE}" pull sub2api; then
    break
  fi
  if [ "$attempt" -eq 5 ]; then
    exit 1
  fi
  sleep $((attempt * 10))
done
docker compose --env-file .env -f "${COMPOSE_FILE}" up -d --remove-orphans

for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:18080/health >/dev/null; then
    docker image prune -f >/dev/null 2>&1 || true
    find releases -name 'sub2api-image-*.tar.gz' -type f -mtime +7 -delete 2>/dev/null || true
    exit 0
  fi
  sleep 2
done

docker compose --env-file .env -f "${COMPOSE_FILE}" ps
docker compose --env-file .env -f "${COMPOSE_FILE}" logs --tail=120 sub2api
exit 1
