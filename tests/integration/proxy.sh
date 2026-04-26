#!/bin/sh
# proxy.sh — integration test for proxy mode
#
# Starts the full stack with --profile proxy, asserts Forgejo and ghproxy
# are reachable, then tears down. Does NOT require real GitHub credentials.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_ENV="${PROJECT_ROOT}/.env.test-proxy"

cleanup() {
    echo "[integration:proxy] Tearing down..."
    docker compose --project-name gjgit-proxy-test \
        --profile proxy \
        --env-file "${TEST_ENV}" \
        -f "${PROJECT_ROOT}/docker-compose.yml" \
        down -v --remove-orphans 2>/dev/null || true
    rm -f "${TEST_ENV}"
    echo "[integration:proxy] Teardown complete."
}
trap cleanup EXIT INT TERM

cat > "${TEST_ENV}" <<EOF
DOMAIN=localhost
LETSENCRYPT_EMAIL=test@localhost
FORGEJO_SSH_PORT=2224
USER_UID=1000
USER_GID=1000
GITEA_URL=http://forgejo:3000
GITEA_ADMIN_USERNAME=testadmin
GITEA_ADMIN_PASSWORD=testpass-proxy-1
GITEA_ADMIN_EMAIL=admin@localhost
GITHUB_REPO=test/repo
GITHUB_TOKEN=fake-token-for-testing
MIRROR_INTERVAL=24h
MIRROR_ISSUES=false
MIRROR_RELEASES=false
MIRROR_LFS=false
GH_PROXY_CACHE_SIZE=512M
GH_PROXY_RATE_LIMIT_RPS=10
EOF

echo "[integration:proxy] Starting proxy stack..."
docker compose --project-name gjgit-proxy-test \
    --profile proxy \
    --env-file "${TEST_ENV}" \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    up -d forgejo bootstrap ghproxy

# ── Wait for Forgejo health ───────────────────────────────────────────────────
echo "[integration:proxy] Waiting for Forgejo..."
MAX_WAIT=90
elapsed=0
while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    HTTP_CODE=$(docker exec gjgit-proxy-test-forgejo-1 \
        curl -s -o /dev/null -w "%{http_code}" \
        http://localhost:3000/api/v1/version 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "[integration:proxy] Forgejo healthy after ${elapsed}s."
        break
    fi
    sleep 5
    elapsed=$(( elapsed + 5 ))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[integration:proxy] FAIL: Forgejo did not start." >&2
        exit 1
    fi
done

# ── Wait for ghproxy health ───────────────────────────────────────────────────
echo "[integration:proxy] Waiting for ghproxy..."
elapsed=0
MAX_WAIT=30
while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    HTTP_CODE=$(docker exec gjgit-proxy-test-ghproxy-1 \
        curl -s -o /dev/null -w "%{http_code}" \
        http://localhost:8080/ 2>/dev/null || echo "000")
    # ghproxy returns 200 on its index page
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "[integration:proxy] ghproxy healthy after ${elapsed}s (HTTP ${HTTP_CODE})."
        break
    fi
    sleep 3
    elapsed=$(( elapsed + 3 ))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[integration:proxy] FAIL: ghproxy did not start within ${MAX_WAIT}s." >&2
        exit 1
    fi
done

echo "[integration:proxy] PASS: Both Forgejo and ghproxy are healthy in proxy mode."
