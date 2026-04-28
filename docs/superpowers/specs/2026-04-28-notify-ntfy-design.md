# notify-ntfy: Push Notifications for Claude Code via ntfy.sh

## Problem

When Claude Code needs human input (permission prompts, questions, task completion), the user must be at their computer. There is no mechanism to get a push notification on mobile devices when Claude is waiting.

## Solution

A bash script + Claude Code hooks that send push notifications via ntfy.sh when Claude Code events require human attention.

## Architecture

```
Claude Code event (Stop / PermissionRequest / Notification)
  → Hook in ~/.claude/settings.json fires
    → ~/.claude/hooks/notify-ntfy.sh reads event JSON from stdin
      → Formats title, message, priority, tags
        → curl POST to https://ntfy.sh/<topic>
          → Push notification arrives on iPhone / any subscribed device
```

## Components

| File | Purpose |
|---|---|
| `~/.claude/hooks/notify-ntfy.sh` | Bash script: reads event, formats notification, sends to ntfy.sh |
| `~/.claude/settings.json` | Hook registrations for Stop, PermissionRequest, Notification |
| `~/.config/notify-ntfy/config.json` | Topic + server config (optional; env vars also work) |

## Configuration

**Resolution order (highest wins):**
1. Environment variables: `NTFY_TOPIC`, `NTFY_SERVER_URL`, `NTFY_TOKEN`
2. Config file: `~/.config/notify-ntfy/config.json`
3. Defaults: server_url = `https://ntfy.sh`; topic = **required** (no default — must be set)

**Config file schema:**
```json
{
  "server_url": "https://ntfy.sh",
  "topic": "hard-to-guess-topic-name"
}
```

## Hook Events

| Event | Title format | Priority | Tags | Message |
|---|---|---|---|---|
| `Stop` | `Done \| <project> \| <branch>` | 3 | `white_check_mark` | `Session completed.` |
| `PermissionRequest` | `Needs approval \| <project> \| <branch>` | 4 | `warning` | `**<tool>**: \`<command>\`` |
| `Notification` | `Alert \| <project> \| <branch>` | 3 | `bell` | Forwarded title + message from event |

## Constraints

- **bash 3.2 compatible** — must run on macOS default `/bin/bash`
- **No Docker dependency** — ntfy.sh hosted service is the default
- **No plugin system** — hooks registered directly in settings.json
- **No external dependencies** beyond `curl`, `jq` (both ship with macOS)
- **No rate limiting** in Phase 1 — add if notifications become noisy
- **No remote approval** in Phase 1 — see Phase 2 roadmap

## Setup Steps (end-to-end)

1. Install ntfy app on iPhone from App Store
2. Open app, subscribe to a topic (use a hard-to-guess name; `uuidgen | tr '[:upper:]' '[:lower:]'` works)
3. Create config file at `~/.config/notify-ntfy/config.json` with topic name
4. Place `notify-ntfy.sh` at `~/.claude/hooks/notify-ntfy.sh` and make executable
5. Add hook entries to `~/.claude/settings.json`
6. Test: `echo '{"hook_event_name":"Stop","cwd":"/tmp/test"}' | ~/.claude/hooks/notify-ntfy.sh`

## Phase 2 Roadmap: Remote Approval Queue

**Goal:** Approve/deny Claude Code actions from iPhone.

**Approach:** Add an MCP server that:
1. Provides `request_approval(description)` tool for Claude to call before sensitive actions
2. Publishes approval request to ntfy.sh with action buttons (Approve/Deny)
3. Polls a response topic (`<topic>-approvals`) for the human's answer
4. Returns `{approved: bool, reason: string}` to Claude

**Key principle:** Direct terminal approval always works. Remote approval is additive — it never blocks the local flow. If you're at the computer, just type y/n. If you've stepped away, use your phone.

**Evaluation of existing solutions for Phase 2:**
- [mcp-ntfy](https://github.com/mambucodev/mcp-ntfy): has publish + poll + action buttons — covers the ntfy API side
- [call-a-human-mcp](https://github.com/nishantmodak/call-a-human-mcp): has blocking `request_approval` tool — different pattern (MCP tool Claude calls voluntarily)

**Phase 1 script is designed to not conflict:** Phase 2 uses separate topics (`<topic>-approvals`) and an MCP server layer, while Phase 1 hooks continue to fire independently.