# notify-ntfy

Push notifications for [Claude Code](https://claude.ai/code) via [ntfy.sh](https://ntfy.sh).

Get notified on your phone when Claude needs your attention — permission requests, session completion, and custom alerts.

---

## Overview

This repo contains **two approaches** to ntfy notifications for Claude Code:

| Approach | Best For | Location |
|----------|----------|----------|
| **Native Hooks** (recommended) | Simple setup, no dependencies | `hooks/notify-ntfy.sh` |
| **Full Plugin** | Advanced features, Docker self-host | `claude-ntfy/` |

The **native hooks approach** is a single bash script that uses Claude Code's built-in hook system. No plugin installation, no Docker, no Node.js — just bash, curl, and jq.

---

## Quick Start (Native Hooks)

### 1. Install the ntfy app

- **iOS**: [App Store](https://apps.apple.com/us/app/ntfy/id1625395537)
- **Android**: [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy) or [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/)

### 2. Subscribe to a topic

Open the app and subscribe to a topic. Use a hard-to-guess name (like a UUID):

```bash
# Generate a topic name
uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-'
# Example: claude-code-jyxtn
```

### 3. Create config file

```bash
mkdir -p ~/.config/notify-ntfy
cat > ~/.config/notify-ntfy/config.json << 'EOF'
{
  "server_url": "https://ntfy.sh",
  "topic": "your-topic-name-here"
}
EOF
```

### 4. Install the hook script

```bash
# Copy the hook to your Claude hooks directory
cp hooks/notify-ntfy.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/notify-ntfy.sh
```

### 5. Register hooks in Claude Code

Edit `~/.claude/settings.json` and add the hook registrations:

```json
{
  "hooks": {
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
}
```

### 6. Test it

```bash
echo '{"hook_event_name":"Stop","cwd":"/tmp/test-project"}' | ~/.claude/hooks/notify-ntfy.sh
```

Check your phone — you should see a notification.

---

## Configuration

Configuration resolution (highest priority wins):

1. **Environment variables**: `NTFY_TOPIC`, `NTFY_SERVER_URL`, `NTFY_TOKEN`
2. **Config file**: `~/.config/notify-ntfy/config.json`
3. **Defaults**: `server_url` = `https://ntfy.sh` (topic is required, no default)

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `NTFY_TOPIC` | Yes* | ntfy topic to publish to |
| `NTFY_SERVER_URL` | No | ntfy server URL (default: `https://ntfy.sh`) |
| `NTFY_TOKEN` | No | Bearer token for authenticated servers |

*Required unless set in config file.

### Config File

```json
{
  "server_url": "https://ntfy.sh",
  "topic": "your-topic-name",
  "token": "optional-bearer-token"
}
```

---

## Hook Events

The script sends notifications for these Claude Code events:

| Event | Title Format | Priority | When It Fires |
|-------|--------------|----------|---------------|
| `Stop` | `Done \| <project> \| <user> @ <host>` | 3 | Claude session ends |
| `PermissionRequest` | `Needs approval \| <project> \| <user> @ <host>` | 4 | Claude needs tool approval |
| `Notification` | `Alert \| <project> \| <user> @ <host>` | 3 | Custom notification from Claude |

Priority levels: 1 (low) → 5 (high). Permission requests use priority 4 to stand out.

---

## Requirements

- **bash** 3.2+ (ships with macOS and most Linux)
- **curl** (ships with macOS and most Linux)
- **jq** (ships with macOS; `apt install jq` / `brew install jq` if missing)

No Docker. No Python. No Node. Just bash.

---

## Alternative: Full Plugin

For a more feature-complete solution with:
- Interactive setup skill (`/setup`)
- Test notification skill (`/test-ntfy`)
- Self-hosted ntfy via Docker
- Bash 4.0+ with full plugin system

See [`claude-ntfy/`](claude-ntfy/) and install with:

```bash
claude plugin add /path/to/claude-code-ntfy/claude-ntfy
```

---

## Security Notes

- **Topic names are public** — anyone who knows your topic can subscribe. Use a hard-to-guess UUID.
- **For sensitive work**: Self-host ntfy or use authenticated topics with tokens.
- **ntfy.sh** is a public service — don't put secrets in notification titles.

---

## Troubleshooting

**No notifications arriving:**
- Verify topic name matches between config and ntfy app
- Check that `~/.claude/hooks/notify-ntfy.sh` is executable (`chmod +x`)
- Test manually: `echo '{"hook_event_name":"Stop","cwd":"/tmp"}' | ~/.claude/hooks/notify-ntfy.sh`
- Check for errors: run the test command above and look for stderr output

**jq not found:**
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt install jq`
- Fedora: `sudo dnf install jq`

**Hooks not firing:**
- Restart Claude Code — hooks are loaded at session start
- Verify `~/.claude/settings.json` syntax: `jq . ~/.claude/settings.json`

---

## License

MIT
