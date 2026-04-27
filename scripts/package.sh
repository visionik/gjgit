#!/bin/sh
# package.sh — bundle gjgit for deployment to any Docker host
#
# Produces: gjgit-deploy-<mode>-<date>.tar.gz in the project root.
# The bundle is self-contained and can be extracted + run on any
# Docker host with docker compose installed.
#
# Usage: task package

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATE="$(date +%Y%m%d-%H%M%S)"

# Detect mode from .env (defaults to standalone)
MODE="standalone"
if [ -f "${PROJECT_DIR}/.env" ]; then
    SAVED_MODE="$(grep '^GJGIT_MODE=' "${PROJECT_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "")"
    [ -n "$SAVED_MODE" ] && MODE="$SAVED_MODE"
fi

BUNDLE_NAME="gjgit-deploy-${MODE}-${DATE}"
BUNDLE_DIR="${PROJECT_DIR}/${BUNDLE_NAME}"
TARBALL="${PROJECT_DIR}/${BUNDLE_NAME}.tar.gz"

echo "[package] Mode: $MODE"
echo "[package] Building bundle: ${BUNDLE_NAME}.tar.gz"

# ── Create bundle directory ───────────────────────────────────────────────────
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# ── Copy files ────────────────────────────────────────────────────────────────

# Always included
cp "${PROJECT_DIR}/docker-compose.yml"  "$BUNDLE_DIR/"
cp "${PROJECT_DIR}/Caddyfile"           "$BUNDLE_DIR/"

# Fly.io configs (useful even for SSH deployments to reference)
[ -f "${PROJECT_DIR}/fly.toml" ]               && cp "${PROJECT_DIR}/fly.toml"               "$BUNDLE_DIR/"
[ -f "${PROJECT_DIR}/fly-proxy.toml" ]         && cp "${PROJECT_DIR}/fly-proxy.toml"         "$BUNDLE_DIR/"
[ -f "${PROJECT_DIR}/Caddyfile.fly" ]          && cp "${PROJECT_DIR}/Caddyfile.fly"          "$BUNDLE_DIR/"
[ -f "${PROJECT_DIR}/docker-compose.fly.yml" ] && cp "${PROJECT_DIR}/docker-compose.fly.yml" "$BUNDLE_DIR/"

# Configs directory (ghproxy, smart-git configs)
if [ -d "${PROJECT_DIR}/configs" ]; then
    cp -r "${PROJECT_DIR}/configs" "$BUNDLE_DIR/"
fi

# Scripts directory (bootstrap, mirror-bootstrap, etc.)
if [ -d "${PROJECT_DIR}/scripts" ]; then
    cp -r "${PROJECT_DIR}/scripts" "$BUNDLE_DIR/"
fi

# Taskfile for convenience on the target host
[ -f "${PROJECT_DIR}/Taskfile.yml" ] && cp "${PROJECT_DIR}/Taskfile.yml" "$BUNDLE_DIR/"

# .env — required, must exist
if [ ! -f "${PROJECT_DIR}/.env" ]; then
    echo "[package] ERROR: .env not found. Run 'task setup' first." >&2
    rm -rf "$BUNDLE_DIR"
    exit 1
fi
cp "${PROJECT_DIR}/.env" "$BUNDLE_DIR/"

# ── Generate deploy README ────────────────────────────────────────────────────
cat > "${BUNDLE_DIR}/DEPLOY.md" << EOF
# gjgit deployment bundle

Mode: **${MODE}**
Built: ${DATE}

## Prerequisites

- Docker Engine 24+ and Docker Compose v2+
- \`task\` (optional but recommended): https://taskfile.dev

## Quick start

\`\`\`sh
# 1. Extract
tar -xzf ${BUNDLE_NAME}.tar.gz
cd ${BUNDLE_NAME}

# 2. Start
$(if [ "$MODE" = "proxy" ]; then
    echo "docker compose --profile proxy up -d"
else
    echo "docker compose up -d"
fi)

# 3. Follow logs
docker compose logs -f
\`\`\`

## Updating .env

Edit \`.env\` in this directory before starting.
All secrets are in that file — keep it secure.

## Stopping

\`\`\`sh
docker compose --profile proxy down       # keep volumes (data preserved)
docker compose --profile proxy down -v    # DESTROY all data
\`\`\`
EOF

# ── Create tarball ────────────────────────────────────────────────────────────
cd "$PROJECT_DIR"
tar -czf "$TARBALL" "$BUNDLE_NAME"
rm -rf "$BUNDLE_DIR"

SIZE="$(du -sh "$TARBALL" | cut -f1)"
echo "[package] Done: $(basename "$TARBALL") (${SIZE})"
echo "[package] Deploy with: task deploy:ssh HOST=user@your-server.com"
echo "           Or copy manually and extract on the target host."
