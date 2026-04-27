#!/bin/sh
# gitea-mirror-entrypoint.sh — token file shim for gitea-mirror
#
# gitea-mirror expects GITEA_TOKEN as an env var, but we derive it from
# a shared volume written by the Forgejo bootstrap container.
# This wrapper reads the token file and exports it before handing off
# to the official docker-entrypoint.sh bundled in the image.

set -eu

TOKEN_FILE="${GITEA_TOKEN_FILE:-}"

if [ -n "$TOKEN_FILE" ] && [ -f "$TOKEN_FILE" ]; then
    GITEA_TOKEN=$(cat "$TOKEN_FILE")
    export GITEA_TOKEN
    echo "[gitea-mirror-entrypoint] GITEA_TOKEN loaded from ${TOKEN_FILE}"
else
    echo "[gitea-mirror-entrypoint] GITEA_TOKEN_FILE not set or not found — proceeding without token (mirror-bootstrap will configure it)"
fi

# Hand off to the image's real entrypoint
exec ./docker-entrypoint.sh "$@"
