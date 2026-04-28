#!/bin/bash
# install.sh: Interactive installer for notify-ntfy
#
# Usage: ./install.sh [--local]
#   --local: Install to project directory (EXPERIMENTAL)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MODE="${1:-}"

if [ "$LOCAL_MODE" = "--local" ]; then
    echo "WARNING: --local mode is experimental and may not work with Claude Code's"
    echo "current hook loading. Global install is recommended."
    echo ""
    read -p "Continue with local install? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Check for required commands
check_deps() {
    local missing=()

    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    echo "Missing required tools: ${missing[*]}"

    if [[ " ${missing[*]} " =~ " jq " ]]; then
        echo ""
        echo "jq is required for JSON handling."
        read -p "Install jq automatically? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_jq
        else
            echo "Please install jq manually:"
            echo "  macOS: brew install jq"
            echo "  Ubuntu/Debian: sudo apt install jq"
            echo "  Fedora: sudo dnf install jq"
            exit 1
        fi
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Please install missing tools and retry."
        exit 1
    fi
}

install_jq() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            echo "Installing jq via Homebrew..."
            brew install jq
        else
            echo "Homebrew not found. Please install jq manually."
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "Installing jq via apt..."
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v dnf >/dev/null 2>&1; then
            echo "Installing jq via dnf..."
            sudo dnf install -y jq
        else
            echo "Could not detect package manager. Please install jq manually."
            exit 1
        fi
    else
        echo "Unsupported OS. Please install jq manually."
        exit 1
    fi
}

# Resolve installation paths based on mode
resolve_paths() {
    if [ "$LOCAL_MODE" = "--local" ]; then
        CONFIG_DIR=".config/notify-ntfy"
        HOOKS_DIR=".claude/hooks"
        SETTINGS_FILE=".claude/settings.json"
        CONFIG_FILE="$CONFIG_DIR/config.json"
    else
        CONFIG_DIR="$HOME/.config/notify-ntfy"
        HOOKS_DIR="$HOME/.claude/hooks"
        SETTINGS_FILE="$HOME/.claude/settings.json"
        CONFIG_FILE="$CONFIG_DIR/config.json"
    fi

    # Create directories if needed
    mkdir -p "$CONFIG_DIR" "$HOOKS_DIR"
}

detect_existing_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "Found existing config at: $CONFIG_FILE"
        echo "Current configuration:"
        jq . "$CONFIG_FILE" 2>/dev/null || echo "  (could not parse config)"
        echo ""
        read -p "Overwrite existing config? [Y/n/s] (s=skip) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            echo "Skipping config creation."
            return 1
        elif [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
    return 0
}
