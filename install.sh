#!/bin/bash
# install.sh: Interactive installer for notify-ntfy
#
# Usage: ./install.sh [--local] [--with-activity-suppression]
#   --local: Install to project directory (EXPERIMENTAL)
#   --with-activity-suppression: Set up shell hooks for activity-based notification suppression

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MODE=""
ACTIVITY_SUPPRESSION=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --local)
            LOCAL_MODE="--local"
            ;;
        --with-activity-suppression)
            ACTIVITY_SUPPRESSION="1"
            ;;
        --help|-h)
            echo "Usage: ./install.sh [--local] [--with-activity-suppression]"
            echo ""
            echo "Options:"
            echo "  --local                       Install to project directory (experimental)"
            echo "  --with-activity-suppression   Set up shell hooks to skip notifications when terminal is active"
            echo "  --help, -h                    Show this help message"
            exit 0
            ;;
    esac
done

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

# --- Activity suppression setup ---

detect_shell() {
    local shell_name
    shell_name=$(basename "$SHELL")
    echo "$shell_name"
}

get_shell_config_file() {
    local shell_name="$1"
    case "$shell_name" in
        zsh)
            echo "$HOME/.zshrc"
            ;;
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo ""
            ;;
    esac
}

is_activity_hook_present() {
    local config_file="$1"
    if [ -f "$config_file" ] && grep -q "notify-ntfy activity tracking" "$config_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

setup_activity_suppression() {
    local shell_name
    shell_name=$(detect_shell)

    echo ""
    echo "Activity Suppression Setup"
    echo "========================="
    echo ""
    echo "This will add a shell hook to skip notifications when your terminal"
    echo "has been active within the last 20 seconds."
    echo ""

    local config_file
    config_file=$(get_shell_config_file "$shell_name")

    if [ -z "$config_file" ]; then
        echo "Could not detect shell config file for: $shell_name"
        echo "Please add the activity hook manually (see docs/CONFIG.md)"
        return 1
    fi

    echo "Detected shell: $shell_name"
    echo "Config file: $config_file"
    echo ""

    if is_activity_hook_present "$config_file"; then
        echo "Activity suppression hook already present in $config_file"
        echo "Skipping setup."
        return 0
    fi

    read -p "Add activity suppression hook to $config_file? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Skipping activity suppression setup."
        echo "You can enable it later by running: ./install.sh --with-activity-suppression"
        return 0
    fi

    # Create config directory if needed
    mkdir -p "$(dirname "$ACTIVITY_FILE")"

    # Add hook based on shell type
    case "$shell_name" in
        zsh)
            cat >> "$config_file" << 'EOF'

# notify-ntfy activity tracking (skip notifications when terminal active)
precmd() {
    mkdir -p ~/.config/notify-ntfy
    date +%s > ~/.config/notify-ntfy/.last-active
}
EOF
            ;;
        bash)
            cat >> "$config_file" << 'EOF'

# notify-ntfy activity tracking (skip notifications when terminal active)
PROMPT_COMMAND='mkdir -p ~/.config/notify-ntfy && date +%s > ~/.config/notify-ntfy/.last-active'
EOF
            ;;
        fish)
            mkdir -p "$(dirname "$config_file")"
            cat >> "$config_file" << 'EOF'

# notify-ntfy activity tracking (skip notifications when terminal active)
function fish_prompt
    mkdir -p ~/.config/notify-ntfy
    date +%s > ~/.config/notify-ntfy/.last-active
    # Your existing prompt logic follows...
end
EOF
            echo ""
            echo "NOTE: Fish shell requires manual integration into your existing fish_prompt function."
            echo "The hook has been appended to $config_file but may need adjustment."
            ;;
        *)
            echo "Unsupported shell: $shell_name"
            echo "Please add the activity hook manually (see docs/CONFIG.md)"
            return 1
            ;;
    esac

    echo ""
    echo "Added activity suppression hook to $config_file"
    echo "To activate: start a new terminal or run: source $config_file"
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
    # Read EFF wordlist from words.txt
    local words=()

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue
        words+=("$line")
    done < "$SCRIPT_DIR/words.txt"

    local num_words=${#words[@]}

    if [ "$num_words" -lt 4 ]; then
        echo "Error: Word list too short ($num_words words). Expected EFF wordlist." >&2
        exit 1
    fi

    # Generate cryptographically random index using /dev/urandom
    random_index() {
        local max="$1"
        local rand_bytes
        # Read 4 bytes from /dev/urandom and convert to unsigned integer
        rand_bytes=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
        echo $((rand_bytes % max))
    }

    # Generate 3 random four-word combinations
    local topics=()
    for i in 1 2 3; do
        local w1="${words[$(random_index $num_words)]}"
        local w2="${words[$(random_index $num_words)]}"
        local w3="${words[$(random_index $num_words)]}"
        local w4="${words[$(random_index $num_words)]}"
        topics+=("${w1}-${w2}-${w3}-${w4}")
    done

    echo ""
    echo "Generated secure topic suggestions (4 words, ~52 bits of entropy):"
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

install_hook() {
    local hook_source="$SCRIPT_DIR/hooks/notify-ntfy.sh"
    local hook_target="$HOOKS_DIR/notify-ntfy.sh"

    if [ ! -f "$hook_source" ]; then
        echo "Error: Hook script not found at $hook_source"
        echo "Make sure you're running install.sh from the repo root."
        exit 1
    fi

    cp "$hook_source" "$hook_target"
    chmod +x "$hook_target"
    echo "Installed hook to: $hook_target"
}

show_settings_diff() {
    echo ""
    echo "Will add the following to $SETTINGS_FILE:"
    echo ""
    echo '  "hooks": {'
    echo '    "Stop": ['
    echo '      {'
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo "            \"command\": \"$HOOKS_DIR/notify-ntfy.sh\","
    echo '            "timeout": 10'
    echo '          }'
    echo '        ]'
    echo '      }'
    echo '    ],'
    echo '    "PermissionRequest": ['
    echo '      {'
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo "            \"command\": \"$HOOKS_DIR/notify-ntfy.sh\","
    echo '            "timeout": 10'
    echo '          }'
    echo '        ]'
    echo '      }'
    echo '    ],'
    echo '    "Notification": ['
    echo '      {'
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo "            \"command\": \"$HOOKS_DIR/notify-ntfy.sh\","
    echo '            "timeout": 10'
    echo '          }'
    echo '        ]'
    echo '      }'
    echo '    ]'
    echo '  }'
    echo ""

    read -p "Modify settings.json? [Y/n/s] (s=skip) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo "Skipping settings.json modification."
        echo "Add hooks manually to $SETTINGS_FILE"
        return 1
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    return 0
}

modify_settings() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        # Create new settings.json
        cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOKS_DIR/notify-ntfy.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOKS_DIR/notify-ntfy.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOKS_DIR/notify-ntfy.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
EOF
        echo "Created new settings.json at: $SETTINGS_FILE"
        return 0
    fi

    # Backup existing file
    local backup="${SETTINGS_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_FILE" "$backup"
    echo "Backed up existing settings to: $backup"

    # Merge hooks into existing settings.json
    local temp_file
    temp_file=$(mktemp)

    jq --arg hook_path "$HOOKS_DIR/notify-ntfy.sh" '
        .hooks.Stop = [{"hooks": [{"type": "command", "command": $hook_path, "timeout": 10}]}]
        | .hooks.PermissionRequest = [{"hooks": [{"type": "command", "command": $hook_path, "timeout": 10}]}]
        | .hooks.Notification = [{"hooks": [{"type": "command", "command": $hook_path, "timeout": 10}]}]
    ' "$SETTINGS_FILE" > "$temp_file"

    if ! jq . "$temp_file" >/dev/null 2>&1; then
        echo "Error: Failed to modify settings.json. Restore from backup: $backup"
        rm "$temp_file"
        exit 1
    fi

    mv "$temp_file" "$SETTINGS_FILE"
    echo "Updated settings.json with hook registrations"
}

send_test_notification() {
    echo ""
    echo "Sending test notification..."

    local test_output
    test_output=$(echo '{"hook_event_name":"Stop","cwd":"/tmp/test"}' | "$HOOKS_DIR/notify-ntfy.sh" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "Test notification sent successfully!"
        echo "Check your phone for the notification."
    else
        echo "Warning: Test notification failed (exit code: $exit_code)"
        echo "Output: $test_output"
        echo ""
        echo "Troubleshooting:"
        echo "  - Verify your topic is subscribed in the ntfy app"
        echo "  - Check that curl and jq are working"
        echo "  - Review the config at: $CONFIG_FILE"
    fi
}

main() {
    echo "notify-ntfy Installer"
    echo "====================="
    echo ""

    check_deps
    resolve_paths

    if detect_existing_config; then
        select_server
        generate_topic
        create_config
    fi

    install_hook

    if show_settings_diff; then
        modify_settings
    fi

    # Setup activity suppression if requested
    if [ -n "$ACTIVITY_SUPPRESSION" ]; then
        setup_activity_suppression
    fi

    send_test_notification

    echo ""
    echo "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Install the ntfy app on your phone"
    echo "  2. Subscribe to topic: $TOPIC"
    echo "  3. Restart Claude Code to pick up the new hooks"
    if [ -n "$ACTIVITY_SUPPRESSION" ]; then
        echo "  4. Start a new terminal or run 'source <your-shell-rc>' to activate activity suppression"
    fi
}

main "$@"
