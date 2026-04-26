#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/work/project/zzv2}"
APP_IMAGE="${APP_IMAGE:-sub2api-zzv2}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
NGINX_LINK="/etc/nginx/conf.d/sub2api-zzv2.conf"
NGINX_TARGET="${DEPLOY_DIR}/nginx/sub2api-zzv2.conf"

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

mkdir -p data postgres_data redis_data releases nginx

if [ ! -f .env ]; then
  umask 077
  cat > .env <<EOF
APP_IMAGE=${APP_IMAGE}
IMAGE_TAG=${IMAGE_TAG}
BIND_HOST=127.0.0.1
HOST_PORT=18080
SERVER_MODE=release
SERVER_FRONTEND_URL=http://111.228.39.25
SERVER_TRUSTED_PROXIES=127.0.0.1
RUN_MODE=standard
TZ=Asia/Shanghai
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=$(openssl rand -hex 24)
POSTGRES_DB=sub2api
DATABASE_MAX_OPEN_CONNS=50
DATABASE_MAX_IDLE_CONNS=10
REDIS_PASSWORD=$(openssl rand -hex 24)
REDIS_DB=0
REDIS_POOL_SIZE=1024
REDIS_MIN_IDLE_CONNS=10
ADMIN_EMAIL=admin@sub2api.local
ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
JWT_SECRET=$(openssl rand -hex 32)
JWT_EXPIRE_HOUR=24
TOTP_ENCRYPTION_KEY=$(openssl rand -hex 32)
SECURITY_URL_ALLOWLIST_ENABLED=false
SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=false
SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS=false
SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS=
UPDATE_PROXY_URL=
GEMINI_OAUTH_CLIENT_ID=
GEMINI_OAUTH_CLIENT_SECRET=
GEMINI_CLI_OAUTH_CLIENT_SECRET=
ANTIGRAVITY_OAUTH_CLIENT_SECRET=
OPS_ENABLED=false
EOF
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

ln -sfn "${NGINX_TARGET}" "${NGINX_LINK}"
nginx -t
systemctl reload nginx

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
