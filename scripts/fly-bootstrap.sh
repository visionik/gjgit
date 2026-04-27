#!/bin/sh
# fly-bootstrap.sh — one-time Fly.io infrastructure setup for gjgit
#
# Creates the Fly app, persistent volumes, and public IP.
# Idempotent — safe to re-run; skips resources that already exist.
#
# Prerequisites:
#   flyctl installed (brew install flyctl)
#   fly auth login
#
# Usage:
#   sh scripts/fly-bootstrap.sh [--proxy]
#
# Options:
#   --proxy    Also create ghproxy_cache volume (proxy/mirror mode)

set -eu

APP_NAME="${FLY_APP:-gjgit}"
REGION="${FLY_REGION:-nrt}"   # nrt=Tokyo; use sin for Singapore or lax for LA
PROXY_MODE=0

for arg in "$@"; do
    case "$arg" in
        --proxy) PROXY_MODE=1 ;;
    esac
done

# ── Verify flyctl auth ────────────────────────────────────────────────────────
echo "[fly-bootstrap] Checking fly auth..."
if ! fly auth whoami > /dev/null 2>&1; then
    echo "[fly-bootstrap] ERROR: Not logged in. Run: fly auth login" >&2
    exit 1
fi
echo "[fly-bootstrap] Authenticated as: $(fly auth whoami)"

# ── Create app (idempotent) ───────────────────────────────────────────────────
echo "[fly-bootstrap] Checking app '${APP_NAME}'..."
if fly status --app "${APP_NAME}" > /dev/null 2>&1; then
    echo "[fly-bootstrap] App '${APP_NAME}' already exists — skipping."
else
    echo "[fly-bootstrap] Creating app '${APP_NAME}'..."
    fly apps create "${APP_NAME}" --machines
    echo "[fly-bootstrap] App created."
fi

# ── Create volumes (idempotent) ───────────────────────────────────────────────
create_volume() {
    VNAME="$1"
    VSIZE="$2"
    echo "[fly-bootstrap] Checking volume '${VNAME}'..."
    if fly volumes list --app "${APP_NAME}" 2>/dev/null | grep -q "${VNAME}"; then
        echo "[fly-bootstrap] Volume '${VNAME}' already exists — skipping."
    else
        echo "[fly-bootstrap] Creating volume '${VNAME}' (${VSIZE}GB) in ${REGION}..."
        fly volumes create "${VNAME}" \
            --app "${APP_NAME}" \
            --region "${REGION}" \
            --size "${VSIZE}" \
            --yes
        echo "[fly-bootstrap] Volume '${VNAME}' created."
    fi
}

# Fly Machines support only 1 volume per machine.
# Single 'forgejo_data' volume (15GB) covers Forgejo data + bootstrap token subdirectory.
create_volume "forgejo_data"  15

if [ "$PROXY_MODE" = "1" ]; then
    create_volume "ghproxy_cache" 20  # ghproxy request/response cache
fi

# ── Allocate public IPv4 (idempotent) ─────────────────────────────────────────
echo "[fly-bootstrap] Checking public IP..."
if fly ips list --app "${APP_NAME}" 2>/dev/null | grep -q 'v4'; then
    echo "[fly-bootstrap] Public IPv4 already allocated — skipping."
else
    echo "[fly-bootstrap] Allocating dedicated IPv4 (required for Let's Encrypt)..."
    fly ips allocate-v4 --app "${APP_NAME}"
    echo "[fly-bootstrap] IPv4 allocated."
fi

echo ""
echo "[fly-bootstrap] Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. cp .env.example .env && edit .env"
echo "  2. task secrets:fly           # Upload secrets to Fly"
echo "  3. task deploy:fly            # Deploy standalone mode"
echo "     task deploy:fly:proxy      # Or: deploy proxy/mirror mode"
