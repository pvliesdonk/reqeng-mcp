#!/bin/bash
# Post-install script: create venv and install reqeng-mcp from PyPI.
set -eu

INSTALL_DIR="/opt/reqeng-mcp"
VENV_DIR="${INSTALL_DIR}/venv"
SERVICE_USER="reqeng-mcp"

# Determine package version — set by nfpm via VERSION env var, or read
# from the installed package metadata as fallback.
PKG_VERSION="${VERSION:-}"

# Create install directory
mkdir -p "$INSTALL_DIR"

# Create or update the virtual environment
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# Upgrade pip and install the package
"${VENV_DIR}/bin/pip" install --quiet --upgrade pip

if [ -n "$PKG_VERSION" ]; then
    "${VENV_DIR}/bin/pip" install --quiet "reqeng-mcp==${PKG_VERSION}"
else
    "${VENV_DIR}/bin/pip" install --quiet "reqeng-mcp"
fi

# Ensure config directory exists
mkdir -p /etc/reqeng-mcp

# Copy example env if no config exists yet
if [ ! -f /etc/reqeng-mcp/env ]; then
    if [ -f /etc/reqeng-mcp/env.example ]; then
        cp /etc/reqeng-mcp/env.example /etc/reqeng-mcp/env
    fi
fi

# Restrict env file permissions — it may contain secrets (tokens, API keys).
if [ -f /etc/reqeng-mcp/env ]; then
    chmod 600 /etc/reqeng-mcp/env
fi

# Reload systemd to pick up the unit file.
# Note: the service is intentionally NOT enabled here — start-on-boot requires
# explicit opt-in by the administrator via: systemctl enable reqeng-mcp
systemctl daemon-reload 2>/dev/null || true

# On upgrade, restart the service if it's already running so the new version is loaded.
if systemctl is-active --quiet reqeng-mcp 2>/dev/null; then
    systemctl restart reqeng-mcp
fi
