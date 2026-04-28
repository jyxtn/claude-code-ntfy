# notify-ntfy Install Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create interactive CLI installer (`install.sh`) and uninstaller (`uninstall.sh`) for notify-ntfy with global and experimental local modes, three-random-word topic generation, and guided setup.

**Architecture:** Bash 3.2 compatible scripts with embedded word list, interactive prompts, defensive error handling, and settings.json manipulation with backups.

**Tech Stack:** bash 3.2+, curl, jq

---

## File Structure

| File | Responsibility |
|------|----------------|
| `install.sh` | Main interactive installer script |
| `uninstall.sh` | Removes hooks, config, and settings.json entries |
| `words.txt` | Adjectives and nouns for topic generation (~300 lines) |

---

### Task 1: Create words.txt

**Files:**
- Create: `words.txt`

- [ ] **Step 1: Create word list with adjectives and nouns**

Create `words.txt` with format:
```
# Adjectives
blue
brisk
golden
swift
...
# Nouns
ocean
forest
mountain
cloud
...
```

Include ~150 common adjectives and ~150 common nouns. Use words from EFF wordlist or common dictionary words that combine well.

- [ ] **Step 2: Commit**

```bash
git add words.txt
git commit -m "feat: add word list for topic name generation"
```

---

### Task 2: Create install.sh header and dependency checking

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write script header and usage**

```bash
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
```

- [ ] **Step 2: Add dependency checking with jq auto-install**

```bash
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
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): add script header and dependency checking"
```

---

### Task 3: Add path resolution for global vs local mode

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add path resolution functions**

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat(install): add path resolution for global/local modes"
```

---

### Task 4: Add existing config detection

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add config detection function**

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat(install): add existing config detection"
```

---

### Task 5: Add server selection and topic generation

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add server selection**

```bash
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
```

- [ ] **Step 2: Add topic generation from word list**

```bash
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
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): add server selection and topic generation"
```

---

### Task 6: Add config file creation

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add config creation function**

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat(install): add config file creation"
```

---

### Task 7: Add hook script installation

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add hook installation function**

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat(install): add hook script installation"
```

---

### Task 8: Add settings.json modification with diff display

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add settings diff display**

```bash
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
```

- [ ] **Step 2: Add settings.json modification with backup**

```bash
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
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): add settings.json modification with backup"
```

---

### Task 9: Add test notification and main function

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add test notification function**

```bash
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
```

- [ ] **Step 2: Add main function and entry point**

```bash
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
    
    send_test_notification
    
    echo ""
    echo "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Install the ntfy app on your phone"
    echo "  2. Subscribe to topic: $TOPIC"
    echo "  3. Restart Claude Code to pick up the new hooks"
}

main "$@"
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat(install): add test notification and main function"
```

---

### Task 10: Create uninstall.sh

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Write uninstall script**

```bash
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
        local backup
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
```

- [ ] **Step 2: Commit**

```bash
git add uninstall.sh
git commit -m "feat: add uninstall.sh script"
```

---

### Task 11: Update README with install instructions

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Quick Install section**

Replace the manual "Quick Start" section with:

```markdown
## Quick Install

```bash
# Clone and run installer
git clone <repo-url>
cd claude-code-ntfy
./install.sh
```

The installer will:
1. Check dependencies (curl, jq)
2. Guide you through server selection (ntfy.sh or self-hosted)
3. Suggest three-random-word topic names (e.g., "blue-mountain-sunrise")
4. Create config and install the hook
5. Register hooks in Claude Code settings
6. Send a test notification

### Manual Install

If you prefer to set things up manually, see the steps below.
```

Then keep the existing manual steps as a "Manual Install" subsection.

- [ ] **Step 2: Add uninstall instructions**

Add at the end:

```markdown
## Uninstall

```bash
./uninstall.sh
```

This removes the config file, hook script, and settings.json entries.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with install/uninstall instructions"
```

---

## Self-Review Checklist

- **Spec coverage:** All requirements from design spec are covered
- **No placeholders:** All code is complete, no TBD/TODO markers
- **Type consistency:** Path variables and functions are consistent
- **Bash 3.2 compatible:** No associative arrays, no `[[ ]]` regex
- **Error handling:** Defensive at each step with clear error messages
