#!/bin/sh
# bootstrap.sh — gjgit first-run bootstrap
#
# Runs as a one-shot Docker service using the Forgejo image.
# On first boot:
#   1. Waits for Forgejo to be healthy (HTTP 200 on /api/v1/version)
#   2. Creates the admin user from env vars (idempotent — skips if exists)
#   3. Generates a Forgejo API token and writes it to /shared/forgejo-token
#
# Idempotency: safe to re-run. If the admin user already exists or the token
# file is already populated, those steps are skipped without error.
#
# Required env vars (from .env):
#   GITEA_URL              Internal Forgejo URL (e.g. http://forgejo:3000)
#   GITEA_ADMIN_USERNAME   Admin username
#   GITEA_ADMIN_PASSWORD   Admin password (change before deploying!)
#   GITEA_ADMIN_EMAIL      Admin email address

set -eu

FORGEJO_URL="${GITEA_URL:-http://forgejo:3000}"
ADMIN_USER="${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
ADMIN_PASS="${GITEA_ADMIN_PASSWORD:?GITEA_ADMIN_PASSWORD is required}"
ADMIN_EMAIL="${GITEA_ADMIN_EMAIL:?GITEA_ADMIN_EMAIL is required}"
TOKEN_FILE="/shared/forgejo-token"
TOKEN_NAME="gjgit-mirror"

# ── Step 1: Wait for Forgejo to be healthy ───────────────────────────────────
echo "[bootstrap] Waiting for Forgejo at ${FORGEJO_URL}..."

MAX_ATTEMPTS=30
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    if curl -sf "${FORGEJO_URL}/api/v1/version" > /dev/null 2>&1; then
        echo "[bootstrap] Forgejo is up (attempt ${attempt}/${MAX_ATTEMPTS})"
        break
    fi
    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "[bootstrap] ERROR: Forgejo did not become healthy after ${MAX_ATTEMPTS} attempts. Aborting." >&2
        exit 1
    fi
    sleep_secs=$(( attempt < 5 ? 2 : 5 ))
    echo "[bootstrap] Not ready yet (attempt ${attempt}/${MAX_ATTEMPTS}), retrying in ${sleep_secs}s..."
    sleep "$sleep_secs"
    attempt=$(( attempt + 1 ))
done

# ── Step 2: Create admin user (idempotent) ───────────────────────────────────
echo "[bootstrap] Checking if admin user '${ADMIN_USER}' exists..."

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/user" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "[bootstrap] Admin user '${ADMIN_USER}' already exists — skipping creation."
else
    echo "[bootstrap] Creating admin user '${ADMIN_USER}'..."
    forgejo admin user create \
        --username "${ADMIN_USER}" \
        --password "${ADMIN_PASS}" \
        --email "${ADMIN_EMAIL}" \
        --admin \
        --must-change-password=false 2>&1 || {
        echo "[bootstrap] ERROR: Failed to create admin user. Check Forgejo logs." >&2
        exit 1
    }
    echo "[bootstrap] Admin user created."
fi

# ── Step 3: Generate API token (idempotent) ───────────────────────────────────
echo "[bootstrap] Checking token file at ${TOKEN_FILE}..."

if [ -s "${TOKEN_FILE}" ]; then
    echo "[bootstrap] Token file already exists and is non-empty — skipping token generation."
    echo "[bootstrap] Bootstrap complete (idempotent run)."
    exit 0
fi

echo "[bootstrap] Generating API token '${TOKEN_NAME}'..."

# Delete existing token with this name if it exists (handles partial failures)
curl -s -o /dev/null \
    -X DELETE \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${FORGEJO_URL}/api/v1/users/${ADMIN_USER}/tokens/${TOKEN_NAME}" 2>/dev/null || true

# Create the token
TOKEN_RESPONSE=$(curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -d "{\"name\":\"${TOKEN_NAME}\"}" \
    "${FORGEJO_URL}/api/v1/users/${ADMIN_USER}/tokens" 2>/dev/null) || {
    echo "[bootstrap] ERROR: Failed to create API token. Check Forgejo logs." >&2
    exit 1
}

# Extract the token value (sha1 field) — avoid printing it to stdout
TOKEN_VALUE=$(echo "$TOKEN_RESPONSE" | \
    sed -n 's/.*"sha1":"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN_VALUE" ]; then
    echo "[bootstrap] ERROR: Could not extract token from API response." >&2
    exit 1
fi

# Write to shared volume — never echo the token
printf '%s' "$TOKEN_VALUE" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"

echo "[bootstrap] Token written to ${TOKEN_FILE}."
echo "[bootstrap] Bootstrap complete."
