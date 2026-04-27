#!/bin/sh
# deploy-ssh.sh — deploy gjgit to a remote Docker host over SSH
#
# Usage: task deploy:ssh HOST=user@your-server.com
#
# Requirements on the remote host:
#   - Docker Engine 24+ with Compose v2
#   - SSH access (key-based auth recommended)
#   - rsync OR scp available locally
#
# What this does:
#   1. Runs 'task package' to build a deployment tarball
#   2. Copies the tarball to the remote host via rsync/scp
#   3. SSHs in, extracts, and runs docker compose up -d
#   4. Tails logs for 30 seconds so you can verify startup

set -eu

HOST="${HOST:?HOST is required. Usage: task deploy:ssh HOST=user@your-server.com}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE_DIR="${REMOTE_DIR:-/opt/gjgit}"

# ── Detect mode ───────────────────────────────────────────────────────────────
MODE="standalone"
if [ -f "${PROJECT_DIR}/.env" ]; then
    SAVED_MODE="$(grep '^GJGIT_MODE=' "${PROJECT_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "")"
    [ -n "$SAVED_MODE" ] && MODE="$SAVED_MODE"
fi

COMPOSE_CMD="docker compose up -d"
[ "$MODE" = "proxy" ] && COMPOSE_CMD="docker compose --profile proxy up -d"

echo "[deploy:ssh] Target: ${HOST}"
echo "[deploy:ssh] Remote path: ${REMOTE_DIR}"
echo "[deploy:ssh] Mode: ${MODE}"
echo ""

# ── Step 1: Build bundle ──────────────────────────────────────────────────────
echo "[deploy:ssh] Building deployment bundle..."
sh "${SCRIPT_DIR}/package.sh"

# Find the newest tarball
TARBALL="$(ls -t "${PROJECT_DIR}"/gjgit-deploy-*.tar.gz 2>/dev/null | head -1)"
if [ -z "$TARBALL" ]; then
    echo "[deploy:ssh] ERROR: No deployment bundle found. Run 'task package' first." >&2
    exit 1
fi

BUNDLE_NAME="$(basename "$TARBALL" .tar.gz)"
echo "[deploy:ssh] Bundle: $(basename "$TARBALL")"
echo ""

# ── Step 2: Copy to remote ────────────────────────────────────────────────────
echo "[deploy:ssh] Copying bundle to ${HOST}:~/ ..."
if command -v rsync >/dev/null 2>&1; then
    rsync -az --progress "$TARBALL" "${HOST}:~/"
else
    scp "$TARBALL" "${HOST}:~/"
fi
echo "[deploy:ssh] Upload complete."
echo ""

# ── Step 3: Extract + start on remote ────────────────────────────────────────
echo "[deploy:ssh] Starting stack on ${HOST}..."
# shellcheck disable=SC2029
ssh "$HOST" "
    set -e
    echo '[remote] Extracting bundle...'
    mkdir -p '${REMOTE_DIR}'
    tar -xzf ~/${BUNDLE_NAME}.tar.gz -C '${REMOTE_DIR}' --strip-components=1
    cd '${REMOTE_DIR}'

    echo '[remote] Pulling latest images...'
    ${COMPOSE_CMD/up -d/pull} 2>/dev/null || true

    echo '[remote] Starting stack...'
    ${COMPOSE_CMD}

    echo '[remote] Stack started. Waiting 10s for health checks...'
    sleep 10
    docker compose ps
"

echo ""
echo "[deploy:ssh] Deployment complete!"
echo ""
echo "  To follow logs:"
echo "    ssh ${HOST} 'cd ${REMOTE_DIR} && docker compose logs -f'"
echo ""
echo "  To open a shell on the server:"
echo "    ssh ${HOST}"
