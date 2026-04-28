#!/bin/sh
# install.sh — gjgit quick-start entry point
#
# The only script users need to run. Handles everything task cannot do for
# itself (installing task, verifying Docker), then hands off to 'task setup'
# which does the rest interactively.
#
# Usage:
#   ./install.sh
#   sh install.sh
#   curl -fsSL https://raw.githubusercontent.com/visionik/gjgit/main/install.sh | sh

set -eu

# ── Formatting ────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n'  "$*"; }

step()  { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
ok()    { green "  ✓ $*"; }
warn()  { yellow "  ⚠ $*"; }
die()   { red "  ✗ $*"; echo ""; exit 1; }

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
bold "  gjgit — self-hosted Forgejo + GitHub mirror"
dim  "  https://github.com/visionik/gjgit"
echo ""

# ── Detect OS ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin) PLATFORM="macOS" ;;
    Linux)  PLATFORM="Linux" ;;
    *)      die "Unsupported OS: $OS. gjgit supports macOS and Linux." ;;
esac

ok "Platform: $PLATFORM ($ARCH)"

# ── Locate project root ───────────────────────────────────────────────────────
# Handles both: running ./install.sh from project root,
# and: curl ... | sh (which has no file path).
if [ -n "${BASH_SOURCE:-}" ]; then
    SCRIPT_PATH="$BASH_SOURCE"
elif [ -f "$0" ] && [ "$0" != "sh" ] && [ "$0" != "bash" ]; then
    SCRIPT_PATH="$0"
else
    SCRIPT_PATH=""
fi

if [ -n "$SCRIPT_PATH" ]; then
    PROJECT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
else
    PROJECT_DIR="$(pwd)"
fi

# If project files aren't here (e.g. curl | sh from a home dir), clone the repo
if [ ! -f "${PROJECT_DIR}/Taskfile.yml" ] || [ ! -f "${PROJECT_DIR}/docker-compose.yml" ]; then
    if ! command -v git >/dev/null 2>&1; then
        die "git is required to install gjgit.\n  Install git and re-run: curl -fsSL https://raw.githubusercontent.com/visionik/gjgit/main/install.sh | sh"
    fi

    CLONE_DIR="${PROJECT_DIR}/gjgit"
    # Don't re-clone if it already exists
    if [ -d "$CLONE_DIR/.git" ]; then
        warn "Found existing clone at ${CLONE_DIR} — updating..."
        git -C "$CLONE_DIR" pull --ff-only 2>/dev/null || true
    else
        step "Cloning gjgit..."
        git clone --depth 1 https://github.com/visionik/gjgit.git "$CLONE_DIR"
        ok "Cloned to ${CLONE_DIR}"
    fi
    PROJECT_DIR="$CLONE_DIR"
fi

ok "Project root: $PROJECT_DIR"
cd "$PROJECT_DIR"

# ── Check: Docker ─────────────────────────────────────────────────────────────
step "Checking prerequisites"

if ! command -v docker >/dev/null 2>&1; then
    echo ""
    die "Docker is not installed.\n  Install Docker Desktop from https://www.docker.com/products/docker-desktop\n  Then re-run: ./install.sh"
fi

# Verify Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo ""
    die "Docker is installed but not running.\n  Start Docker Desktop (or: sudo systemctl start docker) then re-run: ./install.sh"
fi

DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
ok "Docker: $DOCKER_VERSION"

# ── Check: Docker Compose v2 ──────────────────────────────────────────────────
if ! docker compose version >/dev/null 2>&1; then
    echo ""
    die "Docker Compose v2 is required but not found.\n  Upgrade to Docker Desktop 4.x or install the Compose plugin:\n  https://docs.docker.com/compose/install/"
fi

COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || echo 'unknown')"
ok "Docker Compose: $COMPOSE_VERSION"

# ── Install: go-task ──────────────────────────────────────────────────────────
step "Checking go-task (Taskfile runner)"

if command -v task >/dev/null 2>&1; then
    TASK_VERSION="$(task --version 2>/dev/null | head -1 || echo 'installed')"
    ok "go-task: $TASK_VERSION"
else
    warn "go-task not found — installing now..."
    echo ""

    if [ "$PLATFORM" = "macOS" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install go-task
        else
            die "Homebrew is required to install go-task on macOS.\n  Install Homebrew: https://brew.sh\n  Then re-run: ./install.sh"
        fi

    elif [ "$PLATFORM" = "Linux" ]; then
        TASK_VERSION_INSTALL="3.37.2"
        case "$ARCH" in
            x86_64)       TASK_ARCH="amd64" ;;
            aarch64|arm64) TASK_ARCH="arm64" ;;
            armv7l)       TASK_ARCH="arm" ;;
            *) die "Unsupported architecture for go-task: $ARCH" ;;
        esac

        TASK_URL="https://github.com/go-task/task/releases/download/v${TASK_VERSION_INSTALL}/task_linux_${TASK_ARCH}.tar.gz"
        TMP="$(mktemp -d)"
        curl -fsSL "$TASK_URL" -o "${TMP}/task.tar.gz"
        tar -xzf "${TMP}/task.tar.gz" -C "$TMP"

        # Install to ~/.local/bin if /usr/local/bin isn't writable
        if [ -w /usr/local/bin ]; then
            mv "${TMP}/task" /usr/local/bin/task
            chmod +x /usr/local/bin/task
            ok "go-task installed to /usr/local/bin/task"
        else
            mkdir -p "${HOME}/.local/bin"
            mv "${TMP}/task" "${HOME}/.local/bin/task"
            chmod +x "${HOME}/.local/bin/task"
            ok "go-task installed to ~/.local/bin/task"
            # Add to PATH for this session
            export PATH="${HOME}/.local/bin:${PATH}"
            warn "Add ~/.local/bin to your PATH permanently:"
            dim  "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        fi
        rm -rf "$TMP"
    fi

    # Verify
    if ! command -v task >/dev/null 2>&1; then
        die "go-task installation failed. Install manually: https://taskfile.dev/installation"
    fi
    ok "go-task installed: $(task --version 2>/dev/null | head -1)"
fi

# ── Optional: warn about missing recommended tools ────────────────────────────
step "Checking optional tools"

MISSING_OPTIONAL=""

if ! command -v rsync >/dev/null 2>&1; then
    warn "rsync not found — SSH deployments will fall back to scp"
    MISSING_OPTIONAL="$MISSING_OPTIONAL rsync"
fi

if ! command -v fly >/dev/null 2>&1; then
    dim  "  fly CLI not found — only needed for Fly.io deployments"
fi

[ -z "$MISSING_OPTIONAL" ] && ok "All optional tools present"

# ── Hand off to task setup ────────────────────────────────────────────────────
echo ""
bold "  Pre-flight checks passed. Launching setup wizard..."
echo ""

exec task setup
