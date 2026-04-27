#!/bin/sh
# mirror-bootstrap.sh — gitea-mirror first-run bootstrap
#
# Runs as a one-shot Docker service (alpine + curl + jq).
# On first boot:
#   1. Waits for gitea-mirror to be healthy
#   2. Creates the admin account (first signup = admin; idempotent)
#   3. Signs in to get a session cookie
#   4. For each repo in MIRROR_REPOS: imports it and triggers the mirror job
#
# Required env vars:
#   GITEA_MIRROR_URL            Internal URL of the gitea-mirror service
#   GITEA_MIRROR_ADMIN_EMAIL    Admin email for the gitea-mirror web UI
#   GITEA_MIRROR_ADMIN_PASSWORD Admin password for the gitea-mirror web UI
#   MIRROR_REPOS                Comma-separated list of owner/repo to mirror

set -eu

MIRROR_URL="${GITEA_MIRROR_URL:-http://gitea-mirror:4321}"
ADMIN_EMAIL="${GITEA_MIRROR_ADMIN_EMAIL:?GITEA_MIRROR_ADMIN_EMAIL is required}"
ADMIN_PASS="${GITEA_MIRROR_ADMIN_PASSWORD:?GITEA_MIRROR_ADMIN_PASSWORD is required}"
MIRROR_REPOS="${MIRROR_REPOS:-}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
COOKIE_JAR="/tmp/mirror-bootstrap-cookies.txt"

# ── Step 1: Wait for gitea-mirror to be healthy ───────────────────────────────
echo "[mirror-bootstrap] Waiting for gitea-mirror at ${MIRROR_URL}..."

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    if curl -sf "${MIRROR_URL}/api/health" > /dev/null 2>&1; then
        echo "[mirror-bootstrap] gitea-mirror is up (attempt ${attempt}/${MAX_ATTEMPTS})"
        break
    fi
    if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
        echo "[mirror-bootstrap] ERROR: gitea-mirror did not become healthy. Aborting." >&2
        exit 1
    fi
    sleep_secs=$(( attempt < 5 ? 2 : 5 ))
    echo "[mirror-bootstrap] Not ready yet (attempt ${attempt}/${MAX_ATTEMPTS}), retrying in ${sleep_secs}s..."
    sleep "$sleep_secs"
    attempt=$(( attempt + 1 ))
done

# ── Step 2: Create admin account (idempotent) ─────────────────────────────────
echo "[mirror-bootstrap] Attempting to create admin account '${ADMIN_EMAIL}'..."

SIGNUP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\",\"name\":\"Mirror Admin\"}" \
    "${MIRROR_URL}/api/auth/sign-up/email" 2>/dev/null || echo "000")

if [ "$SIGNUP_STATUS" = "200" ] || [ "$SIGNUP_STATUS" = "201" ]; then
    echo "[mirror-bootstrap] Admin account created."
else
    echo "[mirror-bootstrap] Signup returned ${SIGNUP_STATUS} — account may already exist, continuing..."
fi

# ── Step 3: Sign in to get session cookie ─────────────────────────────────────
echo "[mirror-bootstrap] Signing in as '${ADMIN_EMAIL}'..."

SIGNIN_STATUS=$(curl -s -c "${COOKIE_JAR}" -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASS}\"}" \
    "${MIRROR_URL}/api/auth/sign-in/email" 2>/dev/null || echo "000")

if [ "$SIGNIN_STATUS" != "200" ]; then
    echo "[mirror-bootstrap] ERROR: Sign-in failed (HTTP ${SIGNIN_STATUS})." >&2
    exit 1
fi
echo "[mirror-bootstrap] Signed in successfully."

# ── Step 4: Import and mirror each repo in MIRROR_REPOS ───────────────────────
if [ -z "${MIRROR_REPOS}" ]; then
    echo "[mirror-bootstrap] MIRROR_REPOS is not set — skipping repo import."
    echo "[mirror-bootstrap] Bootstrap complete."
    exit 0
fi

# Split comma-separated MIRROR_REPOS (e.g. "owner/repo,owner/repo2")
echo "${MIRROR_REPOS}" | tr ',' '\n' | while IFS= read -r REPO_SPEC; do
    REPO_SPEC=$(echo "$REPO_SPEC" | tr -d ' ')
    [ -z "$REPO_SPEC" ] && continue

    OWNER=$(echo "$REPO_SPEC" | sed 's|/.*||')
    REPO=$(echo "$REPO_SPEC"  | sed 's|.*/||')

    if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
        echo "[mirror-bootstrap] WARNING: invalid repo spec '${REPO_SPEC}', skipping." >&2
        continue
    fi

    echo "[mirror-bootstrap] ── Importing ${OWNER}/${REPO}..."

    # Import (force=true makes it idempotent: refreshes metadata, always returns the repo)
    IMPORT_RESP=$(curl -s -b "${COOKIE_JAR}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"owner\":\"${OWNER}\",\"repo\":\"${REPO}\",\"force\":true}" \
        "${MIRROR_URL}/api/sync/repository" 2>/dev/null || echo '{}')

    REPO_ID=$(echo "$IMPORT_RESP" | jq -r '.repository.id // empty' 2>/dev/null)

    if [ -z "$REPO_ID" ]; then
        echo "[mirror-bootstrap] WARNING: could not get repo ID for ${OWNER}/${REPO}. Response: ${IMPORT_RESP}" >&2
        continue
    fi
    echo "[mirror-bootstrap] Imported ${OWNER}/${REPO} (id=${REPO_ID})"

    # Trigger the actual mirror job (git clone → Forgejo + metadata sync)
    echo "[mirror-bootstrap] Triggering mirror job for ${OWNER}/${REPO}..."
    MIRROR_RESP=$(curl -s -b "${COOKIE_JAR}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"repositoryIds\":[\"${REPO_ID}\"]}" \
        "${MIRROR_URL}/api/job/mirror-repo" 2>/dev/null || echo '{}')

    SUCCESS=$(echo "$MIRROR_RESP" | jq -r '.success // false' 2>/dev/null)
    if [ "$SUCCESS" = "true" ]; then
        echo "[mirror-bootstrap] Mirror job started for ${OWNER}/${REPO}."
    else
        echo "[mirror-bootstrap] WARNING: mirror job may not have started for ${OWNER}/${REPO}. Response: ${MIRROR_RESP}" >&2
    fi
done

echo "[mirror-bootstrap] Bootstrap complete."
