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