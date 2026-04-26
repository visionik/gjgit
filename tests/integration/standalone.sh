#!/bin/sh
# standalone.sh — integration test for standalone mode
#
# Starts the base stack (caddy + forgejo + bootstrap) with a test .env,
# waits for Forgejo to respond, asserts health, then tears down cleanly.
#
# Usage: bash tests/integration/standalone.sh
# Or via Taskfile: task test:integration

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_ENV="${PROJECT_ROOT}/.env.test"

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    echo "[integration:standalone] Tearing down..."
    docker compose --project-name gjgit-test \
        --env-file "${TEST_ENV}" \
        -f "${PROJECT_ROOT}/docker-compose.yml" \
        down -v --remove-orphans 2>/dev/null || true
    rm -f "${TEST_ENV}"
    echo "[integration:standalone] Teardown complete."
}
trap cleanup EXIT INT TERM

# ── Write test .env ───────────────────────────────────────────────────────────
cat > "${TEST_ENV}" <<EOF
DOMAIN=localhost
LETSENCRYPT_EMAIL=test@localhost
FORGEJO_SSH_PORT=2223
USER_UID=1000
USER_GID=1000
GITEA_URL=http://forgejo:3000
GITEA_ADMIN_USERNAME=testadmin
GITEA_ADMIN_PASSWORD=testpass-integration-1
GITEA_ADMIN_EMAIL=admin@localhost
GITHUB_REPO=test/repo
GITHUB_TOKEN=fake-token
MIRROR_INTERVAL=1h
MIRROR_ISSUES=false
MIRROR_RELEASES=false
MIRROR_LFS=false
GH_PROXY_CACHE_SIZE=1G
GH_PROXY_RATE_LIMIT_RPS=10
EOF

# ── Start stack (base profile only — no caddy TLS in test) ───────────────────
echo "[integration:standalone] Starting standalone stack..."
docker compose --project-name gjgit-test \
    --env-file "${TEST_ENV}" \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    up -d forgejo bootstrap

# ── Wait for Forgejo health ───────────────────────────────────────────────────
echo "[integration:standalone] Waiting for Forgejo..."
MAX_WAIT=60
elapsed=0
while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    HTTP_CODE=$(docker exec gjgit-test-forgejo-1 \
        curl -s -o /dev/null -w "%{http_code}" \
        http://localhost:3000/api/v1/version 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "[integration:standalone] Forgejo healthy after ${elapsed}s."
        break
    fi
    sleep 5
    elapsed=$(( elapsed + 5 ))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[integration:standalone] FAIL: Forgejo did not become healthy within ${MAX_WAIT}s." >&2
        exit 1
    fi
done

# ── Assert: version endpoint returns valid JSON ───────────────────────────────
echo "[integration:standalone] Asserting version response..."
VERSION_BODY=$(docker exec gjgit-test-forgejo-1 \
    curl -s http://localhost:3000/api/v1/version 2>/dev/null)

if ! echo "$VERSION_BODY" | grep -q '"version"'; then
    echo "[integration:standalone] FAIL: /api/v1/version did not return expected JSON." >&2
    echo "Response: ${VERSION_BODY}" >&2
    exit 1
fi

echo "[integration:standalone] PASS: Forgejo version endpoint responded correctly."
echo "[integration:standalone] Response: ${VERSION_BODY}"
