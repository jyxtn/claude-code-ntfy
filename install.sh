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

select_server() {
    echo ""
    echo "Select ntfy server:"
    echo "  [1] ntfy.sh (public, default)"
    echo "  [2] Self-hosted"
    read -p "Choice [1-2]: " -n 1 -r
    echo

    case "$REPLY" in
        2)
            read -p "Enter your ntfy server URL (e.g., https://ntfy.yourdomain.com): " SERVER_URL
            SERVER_URL="${SERVER_URL%/}"  # Remove trailing slash
            ;;
        *)
            SERVER_URL="https://ntfy.sh"
            ;;
    esac

    echo "Using server: $SERVER_URL"
}

generate_topic() {
    # Read adjectives and nouns from words.txt
    local adjectives=()
    local nouns=()
    local in_nouns=false

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue

        if [ "$line" = "# Nouns" ]; then
            in_nouns=true
            continue
        fi

        if [ "$in_nouns" = true ]; then
            nouns+=("$line")
        else
            adjectives+=("$line")
        fi
    done < "$SCRIPT_DIR/words.txt"

    local num_adj=${#adjectives[@]}
    local num_nouns=${#nouns[@]}

    # Generate 3 random combinations
    local topics=()
    for i in 1 2 3; do
        local adj1="${adjectives[$((RANDOM % num_adj))]}"
        local noun1="${nouns[$((RANDOM % num_nouns))]}"
        local noun2="${nouns[$((RANDOM % num_nouns))]}"
        topics+=("${adj1}-${noun1}-${noun2}")
    done

    echo ""
    echo "Generated topic suggestions:"
    echo "  1) ${topics[0]}"
    echo "  2) ${topics[1]}"
    echo "  3) ${topics[2]}"
    echo "  4) [Enter your own]"
    read -p "Select [1-4 or type your own]: " choice

    case "$choice" in
        1) TOPIC="${topics[0]}" ;;
        2) TOPIC="${topics[1]}" ;;
        3) TOPIC="${topics[2]}" ;;
        4|"")
            read -p "Enter your topic name: " TOPIC
            ;;
        *)
            TOPIC="$choice"
            ;;
    esac

    echo "Using topic: $TOPIC"
}

create_config() {
    local config
    config=$(cat <<EOF
{
  "server_url": "$SERVER_URL",
  "topic": "$TOPIC"
}
EOF
)

    # Validate JSON
    if ! echo "$config" | jq . >/dev/null 2>&1; then
        echo "Error: Generated invalid JSON. Aborting."
        exit 1
    fi

    echo "$config" > "$CONFIG_FILE"
    echo "Created config at: $CONFIG_FILE"
}
