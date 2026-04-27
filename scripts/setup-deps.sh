#!/bin/sh
# setup-deps.sh — install gum (Charmbracelet TUI toolkit) if not already present
# Supports macOS (brew) and Linux (direct binary download from GitHub releases).

set -eu

GUM_VERSION="0.14.5"
GUM_BIN="${GUM_INSTALL_DIR:-/usr/local/bin}/gum"

# ── Already installed? ────────────────────────────────────────────────────────
if command -v gum >/dev/null 2>&1; then
    echo "[setup-deps] gum already installed: $(command -v gum)"
    exit 0
fi

OS="$(uname -s)"

# ── macOS: use Homebrew ───────────────────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "[setup-deps] ERROR: Homebrew is required on macOS." >&2
        echo "  Install it from https://brew.sh then re-run 'task setup'." >&2
        exit 1
    fi
    echo "[setup-deps] Installing gum via Homebrew..."
    brew install gum
    exit 0
fi

# ── Linux: download binary from GitHub releases ───────────────────────────────
if [ "$OS" = "Linux" ]; then
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  GUM_ARCH="x86_64" ;;
        aarch64|arm64) GUM_ARCH="arm64" ;;
        armv7l)  GUM_ARCH="armv7" ;;
        *)
            echo "[setup-deps] ERROR: Unsupported architecture: $ARCH" >&2
            exit 1
            ;;
    esac

    GUM_URL="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_${GUM_ARCH}.tar.gz"
    TMP_DIR="$(mktemp -d)"

    echo "[setup-deps] Downloading gum ${GUM_VERSION} for Linux/${GUM_ARCH}..."
    curl -fsSL "$GUM_URL" -o "${TMP_DIR}/gum.tar.gz"
    tar -xzf "${TMP_DIR}/gum.tar.gz" -C "$TMP_DIR"

    INSTALL_DIR="${GUM_INSTALL_DIR:-}"
    if [ -z "$INSTALL_DIR" ]; then
        # Try /usr/local/bin (may need sudo), fall back to ~/.local/bin
        if [ -w /usr/local/bin ]; then
            INSTALL_DIR="/usr/local/bin"
        else
            INSTALL_DIR="${HOME}/.local/bin"
            mkdir -p "$INSTALL_DIR"
            echo "[setup-deps] NOTE: Installing to ${INSTALL_DIR} — make sure it is in your PATH."
        fi
    fi

    mv "${TMP_DIR}/gum" "${INSTALL_DIR}/gum"
    chmod +x "${INSTALL_DIR}/gum"
    rm -rf "$TMP_DIR"

    echo "[setup-deps] gum installed to ${INSTALL_DIR}/gum"
    exit 0
fi

echo "[setup-deps] ERROR: Unsupported OS: $OS" >&2
exit 1
