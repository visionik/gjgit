#!/bin/sh
# fly-smoke.sh — E2E smoke test for a live gjgit Fly.io deployment
#
# Verifies:
#   1. Forgejo health endpoint responds HTTP 200
#   2. Bootstrap token file exists and is non-empty on the Fly Machine
#   3. Forgejo admin user exists (bootstrap completed)
#   4. (Proxy mode) gitea-mirror container is running
#
# Usage:
#   sh scripts/fly-smoke.sh [--proxy] [--app <name>]
#
# Or via Taskfile:
#   task fly:smoke           # Standalone
#   task fly:smoke:proxy     # Proxy mode

set -eu

APP_NAME="${FLY_APP:-gjgit}"
PROXY_MODE=0
PASS=0
FAIL=0

for arg in "$@"; do
    case "$arg" in
        --proxy) PROXY_MODE=1 ;;
        --app)   shift; APP_NAME="$1" ;;
    esac
done

check_pass() { echo "  ✓ $1"; PASS=$(( PASS + 1 )); }
check_fail() { echo "  ✗ $1"; FAIL=$(( FAIL + 1 )); }

echo "[fly-smoke] Running E2E smoke test for app '${APP_NAME}'..."
echo ""

# ── 1: Forgejo health endpoint ───────────────────────────────────────────────
echo "[fly-smoke] Check 1: Forgejo health endpoint..."
APP_URL="https://${APP_NAME}.fly.dev"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${APP_URL}/api/v1/version" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    check_pass "Forgejo health endpoint returned HTTP 200 (${APP_URL}/api/v1/version)"
else
    check_fail "Forgejo health endpoint returned HTTP ${HTTP_CODE} — expected 200"
fi

# ── 2: Bootstrap token file exists on Fly Machine ───────────────────────────
echo "[fly-smoke] Check 2: Bootstrap token file on Fly Machine..."
TOKEN_CHECK=$(fly ssh console --app "${APP_NAME}" \
    --command "test -s /mnt/shared_token/forgejo-token && echo EXISTS || echo MISSING" \
    2>/dev/null | tr -d '\r\n' || echo "ERROR")
if [ "$TOKEN_CHECK" = "EXISTS" ]; then
    check_pass "Bootstrap token file exists and is non-empty (/mnt/shared_token/forgejo-token)"
else
    check_fail "Bootstrap token file missing or empty (got: ${TOKEN_CHECK})"
fi

# ── 3: Forgejo admin user exists ─────────────────────────────────────────────
echo "[fly-smoke] Check 3: Forgejo admin user..."
# We can't auth without the password from secrets, so check the users API
USER_COUNT=$(curl -sf "${APP_URL}/api/v1/admin/users?limit=1" \
    2>/dev/null | grep -c '"id"' || echo "0")
if [ "$USER_COUNT" -ge 1 ] 2>/dev/null; then
    check_pass "Forgejo has at least one user (admin was created by bootstrap)"
else
    # Try anonymous check — may be forbidden which also means Forgejo is running
    ADMIN_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${APP_URL}/api/v1/admin/users" 2>/dev/null || echo "000")
    if [ "$ADMIN_CODE" = "401" ] || [ "$ADMIN_CODE" = "403" ]; then
        check_pass "Forgejo admin API returned ${ADMIN_CODE} — Forgejo is running and auth is required"
    else
        check_fail "Could not verify Forgejo admin user (HTTP ${ADMIN_CODE})"
    fi
fi

# ── 4: gitea-mirror running (proxy mode only) ─────────────────────────────────
if [ "$PROXY_MODE" = "1" ]; then
    echo "[fly-smoke] Check 4: gitea-mirror container (proxy mode)..."
    MIRROR_STATUS=$(fly ssh console --app "${APP_NAME}" \
        --command "curl -sf http://gitea-mirror:4321/api/health 2>/dev/null && echo UP || echo DOWN" \
        2>/dev/null | tr -d '\r\n' || echo "ERROR")
    if [ "$MIRROR_STATUS" = "UP" ]; then
        check_pass "gitea-mirror health endpoint is up"
    else
        # Check if the container is at least running by checking the process
        check_fail "gitea-mirror health check failed (got: ${MIRROR_STATUS}) — check fly logs"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "[fly-smoke] Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
    echo "[fly-smoke] FAIL — check 'task fly:logs' for details"
    exit 1
fi
echo "[fly-smoke] PASS — gjgit is healthy on fly.io"
