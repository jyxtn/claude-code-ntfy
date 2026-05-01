#!/bin/bash
# uninstall.sh: Remove notify-ntfy installation
#
# Usage: ./uninstall.sh [--local]

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MODE="${1:-}"

if [ "$LOCAL_MODE" = "--local" ]; then
    CONFIG_FILE=".config/notify-ntfy/config.json"
    HOOK_FILE=".claude/hooks/notify-ntfy.sh"
    SETTINGS_FILE=".claude/settings.json"
else
    CONFIG_FILE="$HOME/.config/notify-ntfy/config.json"
    HOOK_FILE="$HOME/.claude/hooks/notify-ntfy.sh"
    SETTINGS_FILE="$HOME/.claude/settings.json"
fi

# Remove activity suppression hook from shell config
remove_activity_suppression() {
    local shell_name
    shell_name=$(basename "$SHELL")

    local config_file=""
    case "$shell_name" in
        zsh)
            config_file="$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                config_file="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                config_file="$HOME/.bash_profile"
            fi
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            ;;
    esac

    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        return 0
    fi

    if ! grep -q "notify-ntfy activity tracking" "$config_file" 2>/dev/null; then
        return 0
    fi

    echo "Found activity suppression hook in: $config_file"
    read -p "Remove activity suppression hook? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Skipping removal of activity suppression hook."
        return 0
    fi

    # Create temp file without the notify-ntfy block
    # This removes the comment line and everything until a blank line or the end
    awk '
        /# notify-ntfy activity tracking/ {
            # Skip this line and all following non-blank lines
            getline
            while (NF > 0) {
                getline
            }
            next
        }
        { print }
    ' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"

    echo "Removed activity suppression hook from $config_file"
}

echo "notify-ntfy Uninstaller"
echo "======================="
echo ""

# Check what exists
found_something=false

if [ -f "$CONFIG_FILE" ]; then
    echo "Found config: $CONFIG_FILE"
    found_something=true
fi

if [ -f "$HOOK_FILE" ]; then
    echo "Found hook: $HOOK_FILE"
    found_something=true
fi

if ! $found_something; then
    echo "Nothing to uninstall."
    exit 0
fi

echo ""
read -p "Remove these files and settings.json hooks? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Remove config
if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    rmdir "$(dirname "$CONFIG_FILE")" 2>/dev/null || true
    echo "Removed config"
fi

# Remove hook
if [ -f "$HOOK_FILE" ]; then
    rm "$HOOK_FILE"
    echo "Removed hook"
fi

# Remove from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        # Backup
        backup="${SETTINGS_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_FILE" "$backup"

        # Remove hooks
        jq 'del(.hooks.Stop, .hooks.PermissionRequest, .hooks.Notification)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        echo "Removed hooks from settings.json (backup: $backup)"
    else
        echo "jq not found. Please manually remove hooks from $SETTINGS_FILE"
    fi
fi

echo ""
echo "Uninstall complete."

# Offer to remove activity suppression
remove_activity_suppression
