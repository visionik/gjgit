#!/bin/sh
# fly-secrets.sh — import .env into Fly.io secrets
#
# Reads .env and sets each KEY=VALUE pair as a Fly secret.
# Skips comment lines (#) and blank lines.
# Never prints secret values to stdout.
#
# Usage:
#   sh scripts/fly-secrets.sh [--app <name>]
#
# Or via Taskfile:
#   task secrets:fly

set -eu

APP_NAME="${FLY_APP:-gjgit}"
ENV_FILE=".env"

# Parse --app flag
while [ $# -gt 0 ]; do
    case "$1" in
        --app) shift; APP_NAME="$1" ;;
    esac
    shift
done

# ── Verify auth ───────────────────────────────────────────────────────────────
if ! fly auth whoami > /dev/null 2>&1; then
    echo "[fly-secrets] ERROR: Not logged in. Run: fly auth login" >&2
    exit 1
fi

# ── Check .env exists ─────────────────────────────────────────────────────────
if [ ! -f "${ENV_FILE}" ]; then
    echo "[fly-secrets] ERROR: ${ENV_FILE} not found." >&2
    echo "[fly-secrets] Copy .env.example → .env and fill in your values first." >&2
    exit 1
fi

# ── Import secrets ─────────────────────────────────────────────────────────────
echo "[fly-secrets] Importing ${ENV_FILE} to app '${APP_NAME}'..."
echo "[fly-secrets] (secret values are not printed)"

# Filter out comments and blanks, pipe to fly secrets import
grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$' | \
    fly secrets import --app "${APP_NAME}" --stage

echo "[fly-secrets] Secrets staged. They will take effect on next deploy."
echo "[fly-secrets] Run 'task deploy:fly' to deploy with updated secrets."
