# notify-ntfy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bash script + Claude Code hooks that push ntfy.sh notifications when Claude needs human attention.

**Architecture:** A single bash 3.2-compatible script reads hook event JSON from stdin, formats a notification (title, message, priority, tags), and POSTs it to ntfy.sh via curl. Hooks registered directly in `~/.claude/settings.json`. Config via env vars or `~/.config/notify-ntfy/config.json`.

**Tech Stack:** bash 3.2, curl, jq, ntfy.sh HTTP API

---

## File Structure

| File | Responsibility |
|---|---|
| `~/.claude/hooks/notify-ntfy.sh` | Main script: read event JSON, format notification, send to ntfy.sh |
| `~/.config/notify-ntfy/config.json` | User config: topic name, server URL, optional token |
| `~/.claude/settings.json` | Hook registrations (modify existing file, append hooks) |

---

### Task 1: Create config directory and config file

**Files:**
- Create: `~/.config/notify-ntfy/config.json`

- [ ] **Step 1: Generate a topic name and create config file**

```bash
TOPIC=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')
mkdir -p ~/.config/notify-ntfy
cat > ~/.config/notify-ntfy/config.json << EOF
{
  "server_url": "https://ntfy.sh",
  "topic": "${TOPIC}"
}
EOF
```

- [ ] **Step 2: Verify config file**

Run: `cat ~/.config/notify-ntfy/config.json | jq .`

Expected: JSON object with `server_url` and `topic` fields. `server_url` must be `https://ntfy.sh`.

- [ ] **Step 3: Note the topic name for iPhone setup**

Run: `jq -r '.topic' ~/.config/notify-ntfy/config.json`

Expected: A lowercase UUID string. **Save this** — you'll need it to subscribe on the ntfy iPhone app.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: add notify-ntfy config file with generated topic"
```

---

### Task 2: Create the notify-ntfy.sh script

**Files:**
- Create: `~/.claude/hooks/notify-ntfy.sh`

This script must be bash 3.2 compatible. Key differences from claude-ntfy's approach:
- No bash 4 array expansion (`${arr[@]+"${arr[@]}"}`) — use a plain string for headers instead
- No `set -euo pipefail` (the `-u` flag interacts badly with unset variables in bash 3.2) — use `set -eo pipefail` and explicit variable checks
- ntfy.sh as default server, not localhost:8080
- Config file at `~/.config/notify-ntfy/config.json`, not `~/.config/claude-ntfy/config.json`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# notify-ntfy: Push notification for Claude Code events via ntfy.sh
# Reads hook event JSON from stdin, formats notification, sends to ntfy.
#
# Config: env vars (NTFY_TOPIC, NTFY_SERVER_URL, NTFY_TOKEN) > config file > defaults

set -eo pipefail

CONFIG_FILE="${HOME}/.config/notify-ntfy/config.json"

# --- Config resolution ---

resolve_topic() {
  if [ -n "${NTFY_TOPIC:-}" ]; then
    echo "$NTFY_TOPIC"
    return
  fi
  if [ -f "$CONFIG_FILE" ]; then
    local val
    val=$(jq -r '.topic // empty' "$CONFIG_FILE" 2>/dev/null) || true
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo ""  # No default — topic is required
}

resolve_server() {
  if [ -n "${NTFY_SERVER_URL:-}" ]; then
    echo "$NTFY_SERVER_URL"
    return
  fi
  if [ -f "$CONFIG_FILE" ]; then
    local val
    val=$(jq -r '.server_url // empty' "$CONFIG_FILE" 2>/dev/null) || true
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "https://ntfy.sh"
}

resolve_token() {
  if [ -n "${NTFY_TOKEN:-}" ]; then
    echo "$NTFY_TOKEN"
    return
  fi
  if [ -f "$CONFIG_FILE" ]; then
    local val
    val=$(jq -r '.token // empty' "$CONFIG_FILE" 2>/dev/null) || true
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo ""
}

TOPIC=$(resolve_topic)
SERVER_URL=$(resolve_server)
TOKEN=$(resolve_token)

if [ -z "$TOPIC" ]; then
  echo "notify-ntfy: NTFY_TOPIC not set and no topic in $CONFIG_FILE" >&2
  exit 1
fi

URL="${SERVER_URL}/${TOPIC}"

# --- Parse hook event from stdin ---

INPUT=$(cat)

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")
PROJECT=$(printf '%s' "$CWD" | xargs basename 2>/dev/null || echo "")
PROJECT="${PROJECT:-unknown}"

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
USERNAME=$(whoami 2>/dev/null || echo "unknown")

GIT_BRANCH=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ] 2>/dev/null; then
  GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
fi

PROJ="$PROJECT"
if [ -n "$GIT_BRANCH" ]; then
  PROJ="${PROJ} (${GIT_BRANCH})"
fi

# --- Format notification by event type ---

case "$EVENT" in
  Stop)
    TITLE="Done | ${PROJ} | ${USERNAME} @ ${HOSTNAME}"
    MESSAGE="Session completed."
    TAGS="white_check_mark"
    PRIORITY="3"
    ;;
  PermissionRequest)
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    TITLE="Needs approval | ${PROJ} | ${USERNAME} @ ${HOSTNAME}"
    if [ -n "$COMMAND" ]; then
      MESSAGE="**${TOOL}**: \`${COMMAND}\`"
    else
      MESSAGE="**${TOOL}** needs approval"
    fi
    TAGS="warning"
    PRIORITY="4"
    ;;
  Notification)
    NTFY_TITLE=$(printf '%s' "$INPUT" | jq -r '.title // empty' 2>/dev/null || echo "")
    TITLE="Alert | ${PROJ} | ${USERNAME} @ ${HOSTNAME}"
    MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Notification from Claude Code"' 2>/dev/null || echo "Notification from Claude Code")
    if [ -n "$NTFY_TITLE" ]; then
      MESSAGE="**${NTFY_TITLE}**"$'\n'"${MESSAGE}"
    fi
    TAGS="bell"
    PRIORITY="3"
    ;;
  *)
    TITLE="${EVENT:-Event} | ${PROJ} | ${USERNAME} @ ${HOSTNAME}"
    MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Notification from Claude Code"' 2>/dev/null || echo "Notification from Claude Code")
    TAGS="robot"
    PRIORITY="3"
    ;;
esac

# --- Send notification ---

AUTH_HEADER=""
if [ -n "$TOKEN" ]; then
  AUTH_HEADER="-H Authorization: Bearer ${TOKEN}"
fi

# shellcheck disable=SC2086
curl -s $AUTH_HEADER \
  -H "Title: ${TITLE}" \
  -H "Tags: ${TAGS}" \
  -H "Priority: ${PRIORITY}" \
  -H "Markdown: yes" \
  -d "$MESSAGE" \
  -- "$URL" >/dev/null

exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/hooks/notify-ntfy.sh`

- [ ] **Step 3: Syntax check**

Run: `bash -n ~/.claude/hooks/notify-ntfy.sh`

Expected: No output (no syntax errors).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add notify-ntfy.sh hook script"
```

---

### Task 3: Test the script standalone

**Files:**
- No new files — manual testing

This task verifies the script can send a notification to ntfy.sh and it arrives successfully.

- [ ] **Step 1: Send a test Stop event**

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test-project"}' | ~/.claude/hooks/notify-ntfy.sh
```

Expected: No error output. Exit code 0.

- [ ] **Step 2: Verify the notification arrived**

```bash
TOPIC=$(jq -r '.topic' ~/.config/notify-ntfy/config.json)
curl -s "https://ntfy.sh/${TOPIC}/json" | tail -1 | jq .
```

Expected: A JSON object with `title` containing "Done", `message` "Session completed.", `tags` "white_check_mark", `priority` 3.

- [ ] **Step 3: Send a test PermissionRequest event**

```bash
echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/old"},"cwd":"/tmp/test-project"}' | ~/.claude/hooks/notify-ntfy.sh
```

Expected: No error output. Exit code 0.

- [ ] **Step 4: Verify PermissionRequest notification**

```bash
TOPIC=$(jq -r '.topic' ~/.config/notify-ntfy/config.json)
curl -s "https://ntfy.sh/${TOPIC}/json" | tail -1 | jq .
```

Expected: JSON with `title` containing "Needs approval", `message` containing "**Bash**", `priority` 4.

- [ ] **Step 5: Test with missing topic (error case)**

```bash
NTFY_TOPIC="" NTFY_SERVER_URL="https://ntfy.sh" bash -c 'echo "{\"hook_event_name\":\"Stop\",\"cwd\":\"/tmp/test\"}" | ~/.claude/hooks/notify-ntfy.sh' 2>&1; echo "exit: $?"
```

Expected: Error message containing "NTFY_TOPIC not set". Exit code 1.

- [ ] **Step 6: Verify notification on iPhone (manual)**

At this point, if the ntfy app is installed on your iPhone and subscribed to the topic, you should see the test notifications appear on your phone.

---

### Task 4: Register hooks in settings.json

**Files:**
- Modify: `~/.claude/settings.json` — add Stop, PermissionRequest, Notification hooks alongside existing PreToolUse hook

The existing settings.json has a `hooks.PreToolUse` array. We need to add `hooks.Stop`, `hooks.PermissionRequest`, and `hooks.Notification` without disrupting the existing configuration.

- [ ] **Step 1: Add the three new hook entries**

The current `hooks` section is:
```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Grep|Glob|Read|Search",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/cbm-code-discovery-gate"
        }
      ]
    }
  ]
}
```

After modification, it should be:
```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Grep|Glob|Read|Search",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/cbm-code-discovery-gate"
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/notify-ntfy.sh",
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
          "command": "~/.claude/hooks/notify-ntfy.sh",
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
          "command": "~/.claude/hooks/notify-ntfy.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `jq . ~/.claude/settings.json > /dev/null && echo "valid" || echo "invalid"`

Expected: "valid"

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: register notify-ntfy hooks in Claude Code settings"
```

---

### Task 5: End-to-end test with Claude Code

**Files:**
- No new files — manual testing

This task verifies that Claude Code actually fires the hooks and notifications arrive.

- [ ] **Step 1: Restart Claude Code session**

The hooks from settings.json are loaded at session start. Exit and re-enter Claude Code to pick up the new hook registrations.

- [ ] **Step 2: Trigger a Notification event**

Ask Claude a question (e.g., type a simple prompt). Claude's response should trigger a Notification or Stop event depending on the interaction.

- [ ] **Step 3: Verify notification arrived on iPhone**

Check the ntfy app on your iPhone for the notification.

- [ ] **Step 4: Trigger a PermissionRequest event**

Ask Claude to do something that requires a permission prompt (e.g., "run `ls /tmp`"). When the permission dialog appears, verify a "Needs approval" notification arrives on your iPhone.

- [ ] **Step 5: Approve in terminal (not phone)**

Approve the permission in the terminal to verify that local approval still works as the primary path.