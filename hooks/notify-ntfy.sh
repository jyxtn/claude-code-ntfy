#!/bin/bash
# notify-ntfy: Push notification for Claude Code events via ntfy.sh
# Reads hook event JSON from stdin, formats notification, sends to ntfy.
#
# Config resolution (highest priority first):
#   1. Environment variables (NTFY_TOPIC, NTFY_SERVER_URL, NTFY_TOKEN)
#   2. Local project config (.notify-ntfy.json in project directory)
#   3. Global config (~/.config/notify-ntfy/config.json)
#   4. Defaults
#
# Activity suppression: Set NTFY_ACTIVITY_THRESHOLD (seconds) to skip notifications
# when terminal was recently active. Requires shell hook to write timestamp file.

set -eo pipefail

GLOBAL_CONFIG="${HOME}/.config/notify-ntfy/config.json"
ACTIVITY_FILE="${HOME}/.config/notify-ntfy/.last-active"
ACTIVITY_THRESHOLD="${NTFY_ACTIVITY_THRESHOLD:-20}"

# Parse input early to get CWD for local config detection
INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Determine which config file to use
if [ -n "$CWD" ] && [ -f "${CWD}/.notify-ntfy.json" ]; then
  CONFIG_FILE="${CWD}/.notify-ntfy.json"
elif [ -n "$CWD" ] && [ -f "${CWD}/.claude/notify-ntfy.json" ]; then
  CONFIG_FILE="${CWD}/.claude/notify-ntfy.json"
else
  CONFIG_FILE="$GLOBAL_CONFIG"
fi

# --- Activity suppression ---

should_skip_notification() {
  if [ -z "$ACTIVITY_THRESHOLD" ] || [ "$ACTIVITY_THRESHOLD" -le 0 ]; then
    return 1
  fi

  if [ ! -f "$ACTIVITY_FILE" ]; then
    return 1
  fi

  local last_active now elapsed
  last_active=$(cat "$ACTIVITY_FILE" 2>/dev/null) || return 1
  now=$(date +%s)

  if ! [[ "$last_active" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  elapsed=$((now - last_active))

  if [ "$elapsed" -lt "$ACTIVITY_THRESHOLD" ]; then
    return 0
  fi

  return 1
}

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
  echo ""
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

# --- Parse remaining hook event data ---

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
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

if should_skip_notification; then
  exit 0
fi

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