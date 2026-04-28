# notify-ntfy

Push notifications for [Claude Code](https://claude.ai/code) via [ntfy.sh](https://ntfy.sh).

Get notified on your phone when Claude needs your attention — permission requests, session completion, and custom alerts.

---

## What It Does

A single bash script that plugs into Claude Code's native hook system. When Claude fires a `Stop`, `PermissionRequest`, or `Notification` event, you get a push notification on your phone.

No plugin system. No Docker. No dependencies beyond bash, curl, and jq.

---

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

If you prefer to set things up manually:

1. Install the ntfy app (iOS: [App Store](https://apps.apple.com/us/app/ntfy/id1625395537), Android: [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy) or [F-Droid](https://f-droid.org/packages/io.heckel.ntfy/))
2. Subscribe to a topic in the app
3. Create `~/.config/notify-ntfy/config.json` with your topic
4. Copy `hooks/notify-ntfy.sh` to `~/.claude/hooks/`
5. Add hook registrations to `~/.claude/settings.json` (see [CONFIG.md](docs/CONFIG.md) for details)

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

See [docs/CONFIG.md](docs/CONFIG.md) for more configuration options including self-hosted ntfy.

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

## Uninstall

```bash
./uninstall.sh
```

This removes the config file, hook script, and settings.json entries.

---

## License

MIT
