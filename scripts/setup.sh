#!/bin/sh
# setup.sh — gjgit interactive setup wizard
#
# Requires: gum  (install: brew install gum  OR  task setup:deps)
# Usage:    task setup
#
# Writes a complete .env to the project root.
# All secrets are masked in the review screen.
# Existing .env is backed up before overwrite.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env"
TMP_DIR="/tmp/gjgit-setup"

# ── Style palette ─────────────────────────────────────────────────────────────
C_ACCENT="212"   # pink  — headers, selections
C_DIM="242"      # gray  — hints, descriptions
C_OK="82"        # green — success
C_WARN="214"     # amber — warnings
C_ERR="196"      # red   — errors

# ── Helpers ───────────────────────────────────────────────────────────────────

header() {
    clear
    gum style \
        --border rounded \
        --border-foreground "$C_ACCENT" \
        --padding "1 4" --margin "1 2" --bold \
        "  gjgit setup  "
}

section() {
    echo ""
    gum style --foreground "$C_ACCENT" --bold --margin "0 2" "▸ $1"
    echo ""
}

hint() {
    gum style --foreground "$C_DIM" --margin "0 4" "$1"
}

ok() {
    gum style --foreground "$C_OK" --margin "0 2" "✓ $1"
}

warn() {
    gum style --foreground "$C_WARN" --margin "0 2" "⚠ $1"
}

gen_password() {
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | dd bs=1 count=24 2>/dev/null || \
        openssl rand -hex 12
}

gen_secret() {
    openssl rand -base64 32 2>/dev/null || \
        LC_ALL=C tr -dc 'A-Za-z0-9+/=' </dev/urandom | dd bs=1 count=44 2>/dev/null
}

# Write a field value to tmp store
set_field() { printf '%s' "$2" > "${TMP_DIR}/$1"; }

# Read a field value from tmp store (returns empty string if not set)
get_field() {
    local f="${TMP_DIR}/$1"
    [ -f "$f" ] && cat "$f" || echo ""
}

# Prompt for a single field.
# prompt_field VAR_NAME "Description" "default" secret(true|false)
prompt_field() {
    local name="$1" desc="$2" default="$3" secret="${4:-false}"
    local current; current="$(get_field "$name")"
    # Use current value as default if already set
    [ -n "$current" ] && default="$current"

    hint "$desc"

    local val
    if [ "$secret" = "true" ]; then
        local ph="(leave blank to auto-generate)"
        val="$(gum input --password \
            --placeholder "$ph" \
            --prompt "  $name: " \
            --width 60 || echo "")"
        # Auto-generate if left blank
        if [ -z "$val" ]; then
            if echo "$name" | grep -qi "secret\|auth_secret\|better_auth"; then
                val="$(gen_secret)"
            else
                val="$(gen_password)"
            fi
            hint "(auto-generated)"
        fi
    else
        val="$(gum input \
            --value "$default" \
            --placeholder "${default:-...}" \
            --prompt "  $name: " \
            --width 60 || echo "$default")"
        # Fall back to default if empty
        [ -z "$val" ] && val="$default"
    fi

    set_field "$name" "$val"
}

# Display a masked value for secrets in review
mask() {
    local val="$1"
    [ -z "$val" ] && echo "(not set)" && return
    printf '%.0s●' $(seq 1 8)
    echo " (${#val} chars)"
}

# ── Variable definitions ──────────────────────────────────────────────────────
# Format: NAME|description|default|secret|mode
# mode: both = standalone + proxy, proxy = proxy only
#
# Stored in a newline-separated string (sh has no arrays).

VARS_BOTH='
DOMAIN|Your public domain (e.g. git.mycompany.com)|git.yourdomain.com|false|both
LETSENCRYPT_EMAIL|Email for TLS certificate (Let'\''s Encrypt)|admin@yourdomain.com|false|both
FORGEJO_SSH_PORT|Host port for SSH git access|2222|false|both
USER_UID|Unix UID for the Forgejo process (match your server user)|1000|false|both
USER_GID|Unix GID for the Forgejo process|1000|false|both
GITEA_ADMIN_USERNAME|Forgejo admin username (not "admin" — that is reserved)|gitadmin|false|both
GITEA_ADMIN_PASSWORD|Forgejo admin password — leave blank to auto-generate||true|both
GITEA_ADMIN_EMAIL|Forgejo admin email|admin@yourdomain.com|false|both
FORGEJO__server__ROOT_URL|Public URL for Forgejo clone links (include trailing slash)|https://git.yourdomain.com/|false|both
FORGEJO__server__SSH_DOMAIN|SSH hostname shown in git clone URLs|git.yourdomain.com|false|both'

VARS_PROXY='
GITHUB_TOKEN|GitHub Personal Access Token (needs repo scope for private repos)||true|proxy
GITHUB_USERNAME|GitHub username to mirror from||false|proxy
MIRROR_REPOS|Repos to mirror — comma-separated owner/repo (e.g. alice/foo,alice/bar)||false|proxy
GITEA_MIRROR_INTERVAL|How often to sync (e.g. 15m, 1h, 6h)|15m|false|proxy
MIRROR_ISSUES|Mirror GitHub issues and PRs|true|false|proxy
MIRROR_RELEASES|Mirror GitHub releases and assets|true|false|proxy
MIRROR_LFS|Mirror Git LFS objects|true|false|proxy
GITEA_MIRROR_ADMIN_EMAIL|Admin email for the Gitea Mirror web UI|admin@yourdomain.com|false|proxy
GITEA_MIRROR_ADMIN_PASSWORD|Admin password for Gitea Mirror UI — leave blank to auto-generate||true|proxy
BETTER_AUTH_SECRET|Session signing secret — leave blank to auto-generate||true|proxy
SCHEDULE_ENABLED|Run automatic sync on interval|true|false|proxy
AUTO_IMPORT_REPOS|Bulk-import ALL your GitHub repos (set false to use MIRROR_REPOS list only)|false|false|proxy
GH_PROXY_CACHE_SIZE|Max disk for GitHub proxy cache|20G|false|proxy
GH_PROXY_RATE_LIMIT_RPS|Rate limit per IP for GitHub proxy (0 = unlimited)|200|false|proxy'

# Get all vars for a given mode
vars_for_mode() {
    local mode="$1"
    if [ "$mode" = "standalone" ]; then
        echo "$VARS_BOTH"
    else
        printf '%s\n%s' "$VARS_BOTH" "$VARS_PROXY"
    fi
}

# ── Prompt all fields for a mode ──────────────────────────────────────────────
prompt_all_fields() {
    local mode="$1"
    vars_for_mode "$mode" | while IFS='|' read -r name desc default secret _mode; do
        [ -z "$name" ] && continue
        prompt_field "$name" "$desc" "$default" "$secret"
        echo ""
    done
}

# ── Review screen ─────────────────────────────────────────────────────────────
show_review() {
    local mode="$1"
    section "Review your configuration"

    vars_for_mode "$mode" | while IFS='|' read -r name desc default secret _mode; do
        [ -z "$name" ] && continue
        local val; val="$(get_field "$name")"
        if [ "$secret" = "true" ]; then
            printf "  %-40s %s\n" "$name" "$(mask "$val")"
        else
            printf "  %-40s %s\n" "$name" "$val"
        fi
    done
    echo ""
}

# ── Edit-field loop ───────────────────────────────────────────────────────────
edit_field_loop() {
    local mode="$1"

    while true; do
        header
        show_review "$mode"

        ACTION="$(gum choose \
            --cursor.foreground "$C_ACCENT" \
            --selected.foreground "$C_ACCENT" \
            "✓  Looks good — write .env" \
            "✎  Edit a field" \
            "↺  Start over" \
            "✕  Quit without saving")"

        case "$ACTION" in
            "✓"*)  return 0 ;;
            "✕"*)  echo ""; warn "Cancelled — .env not written."; exit 0 ;;
            "↺"*)  return 1 ;;  # restart
            "✎"*)
                # Build list of fields to choose from
                local choices=""
                vars_for_mode "$mode" | while IFS='|' read -r name desc default secret _mode; do
                    [ -z "$name" ] && continue
                    local val; val="$(get_field "$name")"
                    if [ "$secret" = "true" ]; then
                        printf '%s  %s\n' "$name" "(secret, ${#val} chars)"
                    else
                        printf '%s  %s\n' "$name" "$val"
                    fi
                done > /tmp/gjgit-field-choices.txt

                CHOSEN="$(gum choose \
                    --cursor.foreground "$C_ACCENT" \
                    --height 20 \
                    $(cat /tmp/gjgit-field-choices.txt | awk '{print $1}'))"

                # Re-prompt just that field
                vars_for_mode "$mode" | while IFS='|' read -r name desc default secret _mode; do
                    [ -z "$name" ] && continue
                    [ "$name" = "$CHOSEN" ] || continue
                    header
                    section "Edit: $name"
                    prompt_field "$name" "$desc" "$default" "$secret"
                done
                ;;
        esac
    done
}

# ── Write .env ────────────────────────────────────────────────────────────────
write_env() {
    local mode="$1"

    # Back up existing .env
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${ENV_FILE}.bak"
        warn "Existing .env backed up to .env.bak"
    fi

    cat > "$ENV_FILE" << 'HEADER'
# ============================================================
# gjgit — Environment Configuration (generated by task setup)
# NEVER commit this file — it contains secrets.
# ============================================================

HEADER

    # Write mode marker
    printf '# Mode: %s\n' "$mode" >> "$ENV_FILE"
    printf 'GJGIT_MODE=%s\n\n' "$mode" >> "$ENV_FILE"

    # Standalone vars
    printf '# ── Forgejo + Caddy ──────────────────────────────────────────────────────\n' >> "$ENV_FILE"
    echo "$VARS_BOTH" | while IFS='|' read -r name desc default secret _mode; do
        [ -z "$name" ] && continue
        local val; val="$(get_field "$name")"
        printf '%s=%s\n' "$name" "$val" >> "$ENV_FILE"
    done

    # Proxy-only vars
    if [ "$mode" = "proxy" ]; then
        printf '\n# ── Proxy / mirror mode ─────────────────────────────────────────────────\n' >> "$ENV_FILE"
        echo "$VARS_PROXY" | while IFS='|' read -r name desc default secret _mode; do
            [ -z "$name" ] && continue
            local val; val="$(get_field "$name")"
            printf '%s=%s\n' "$name" "$val" >> "$ENV_FILE"
        done
    fi

    # Always write GITEA_URL (internal, not prompted)
    printf '\n# Internal Forgejo URL (do not change)\n' >> "$ENV_FILE"
    printf 'GITEA_URL=http://forgejo:3000\n' >> "$ENV_FILE"

    chmod 600 "$ENV_FILE"
}

# ── Deploy prompt ─────────────────────────────────────────────────────────────
show_deploy_prompt() {
    local mode="$1"
    section "Your .env is ready. What would you like to do next?"

    DEPLOY_ACTION="$(gum choose \
        --cursor.foreground "$C_ACCENT" \
        --selected.foreground "$C_ACCENT" \
        "🚀  Deploy locally now" \
        "🖥   Deploy to a remote server via SSH" \
        "✈   Deploy to Fly.io" \
        "📦  Build deployment bundle only" \
        "💾  Save .env only — I'll deploy manually")"

    case "$DEPLOY_ACTION" in
        "🚀"*)
            section "Deploying locally..."
            if [ "$mode" = "proxy" ]; then
                docker compose --profile proxy up -d
            else
                docker compose up -d
            fi
            echo ""
            ok "Stack is running locally."
            gum style --foreground "$C_DIM" --margin "0 4" \
                "Forgejo:      http://localhost:3000"
            [ "$mode" = "proxy" ] && gum style --foreground "$C_DIM" --margin "0 4" \
                "Gitea Mirror: http://localhost:4321"
            ;;

        "🖥"*)
            section "Remote SSH deployment"
            hint "Enter the SSH target (e.g. ubuntu@203.0.113.10 or deploy@myserver.com)"
            echo ""
            SSH_HOST="$(gum input \
                --prompt "  SSH host: " \
                --placeholder "user@your-server.com" \
                --width 60)"
            if [ -z "$SSH_HOST" ]; then
                warn "No host entered — skipping deployment."
            else
                REMOTE_DIR="${REMOTE_DIR:-/opt/gjgit}"
                hint "Remote install path (default: ${REMOTE_DIR})"
                CUSTOM_DIR="$(gum input \
                    --prompt "  Remote path: " \
                    --value "$REMOTE_DIR" \
                    --width 60)"
                [ -n "$CUSTOM_DIR" ] && REMOTE_DIR="$CUSTOM_DIR"
                echo ""
                gum spin --spinner dot --title "Building deployment bundle..." -- \
                    sh "${SCRIPT_DIR}/package.sh"
                HOST="$SSH_HOST" REMOTE_DIR="$REMOTE_DIR" sh "${SCRIPT_DIR}/deploy-ssh.sh"
            fi
            ;;

        "✈"*)
            section "Fly.io deployment"
            hint "Make sure you are logged in with 'fly auth login' and have a Fly app configured."
            echo ""
            gum spin --spinner dot --title "Uploading secrets to Fly.io..." -- \
                sh "${SCRIPT_DIR}/fly-secrets.sh"
            if [ "$mode" = "proxy" ]; then
                fly deploy --config "${PROJECT_DIR}/fly-proxy.toml"
            else
                fly deploy --config "${PROJECT_DIR}/fly.toml"
            fi
            ok "Deployed to Fly.io."
            ;;

        "📦"*)
            gum spin --spinner dot --title "Building deployment bundle..." -- \
                sh "${SCRIPT_DIR}/package.sh"
            ok "Bundle ready. Copy it to your server and extract, then run: docker compose up -d"
            ;;

        "💾"*)
            ok ".env saved."
            echo ""
            gum style --foreground "$C_DIM" --margin "0 4" \
                "When you're ready:"
            gum style --foreground "$C_DIM" --margin "0 6" \
                "Local:   task deploy:local"
            gum style --foreground "$C_DIM" --margin "0 6" \
                "SSH:     task deploy:ssh HOST=user@your-server.com"
            gum style --foreground "$C_DIM" --margin "0 6" \
                "Fly.io:  task secrets:fly && task deploy:fly"
            ;;
    esac
    echo ""
}

# ── Main loop ─────────────────────────────────────────────────────────────────
main() {
    mkdir -p "$TMP_DIR"

    while true; do
        header

        gum style --foreground "$C_DIM" --margin "0 2" \
            "This wizard writes .env for your gjgit deployment."
        gum style --foreground "$C_DIM" --margin "0 2" \
            "Secrets are masked in the review screen. Leave password fields blank to auto-generate."
        echo ""

        section "Select operating mode"

        MODE="$(gum choose \
            --cursor.foreground "$C_ACCENT" \
            --selected.foreground "$C_ACCENT" \
            "standalone  — Forgejo + Caddy (git hosting only)" \
            "proxy       — + gitea-mirror + ghproxy (GitHub mirroring + acceleration)")"
        MODE="$(echo "$MODE" | awk '{print $1}')"

        echo ""
        gum style --foreground "$C_DIM" --margin "0 2" "Mode: $MODE"
        echo ""

        section "Enter configuration"
        hint "Press Enter to accept defaults. Leave secrets blank to auto-generate."
        echo ""

        prompt_all_fields "$MODE"

        # Review + edit loop — returns 0 to confirm, 1 to restart
        if edit_field_loop "$MODE"; then
            break
        fi
        # restart: clear tmp and loop
        rm -rf "$TMP_DIR"
        mkdir -p "$TMP_DIR"
    done

    gum spin --spinner dot --title "Writing .env..." -- sh -c "sleep 1"
    write_env "$MODE"

    ok ".env written to: $ENV_FILE"
    show_deploy_prompt "$MODE"
}

main "$@"
