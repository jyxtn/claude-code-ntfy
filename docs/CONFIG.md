# Configuration Guide

Configuration for `notify-ntfy.sh` can be provided via environment variables, project-local config, or global config.

## Resolution Order

Configuration is resolved in this priority (highest wins):

1. **Environment variables** (`NTFY_TOPIC`, `NTFY_SERVER_URL`, `NTFY_TOKEN`)
2. **Project-local config** (`.notify-ntfy.json` in project directory)
3. **Global config** (`~/.config/notify-ntfy/config.json`)
4. **Defaults** (only `server_url` has a default; `topic` is required)

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NTFY_TOPIC` | Yes* | — | ntfy topic to publish to |
| `NTFY_SERVER_URL` | No | `https://ntfy.sh` | ntfy server URL |
| `NTFY_TOKEN` | No | — | Bearer token for authenticated servers |

*Required unless set in config file.

## Config File

Create `~/.config/notify-ntfy/config.json`:

```json
{
  "server_url": "https://ntfy.sh",
  "topic": "your-topic-name-here",
  "token": "optional-bearer-token"
}
```

### Config File Only (No Env Vars)

```json
{
  "server_url": "https://ntfy.sh",
  "topic": "claude-code-jyxtn"
}
```

### With Authentication (Self-Hosted)

```json
{
  "server_url": "https://ntfy.yourdomain.com",
  "topic": "claude-alerts",
  "token": "tk_your_token_here"
}
```

## Project-Local Configuration

Use a different topic per project by creating `.notify-ntfy.json` in your project root:

```json
{
  "server_url": "https://ntfy.sh",
  "topic": "abacus-zebra-quartz-meadow"
}
```

The hook checks these locations in order:
1. `.notify-ntfy.json` (project root)
2. `.claude/notify-ntfy.json` (Claude config directory)
3. Falls back to global config

### Use Cases

**Team project with shared notifications:**
```json
{
  "server_url": "https://ntfy.sh",
  "topic": "team-infrastructure-alerts"
}
```
Commit this to the repo so the whole team gets notified.

**Personal project with private notifications:**
```json
{
  "server_url": "https://ntfy.sh",
  "topic": "abacus-zebra-quartz-meadow"
}
```
Add to `.gitignore` to keep your topic private.

**Different servers per project:**
- Work projects → Self-hosted ntfy server
- Personal projects → ntfy.sh public server

## Self-Hosted ntfy

To run your own ntfy server instead of using ntfy.sh:

```yaml
# docker-compose.yml
version: "3"
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    command: serve
    volumes:
      - ./ntfy-cache:/var/cache/ntfy
      - ./ntfy-config:/etc/ntfy
    ports:
      - "8080:80"
```

Then set `server_url` to `http://localhost:8080` (or your domain with HTTPS).

## Topic Naming

**Important:** Topic names are public. Anyone who knows your topic can subscribe to it.

**Recommended:** Use a hard-to-guess UUID:

```bash
uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-'
```

## Examples

### Basic ntfy.sh setup

```bash
mkdir -p ~/.config/notify-ntfy
cat > ~/.config/notify-ntfy/config.json << 'EOF'
{
  "server_url": "https://ntfy.sh",
  "topic": "claude-code-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-8)"
}
EOF
```

### Environment override (for testing)

```bash
NTFY_TOPIC=test-topic ~/.claude/hooks/notify-ntfy.sh < test-event.json
```

---

## Activity Suppression

Skip notifications when you're actively using the terminal. Useful when you're watching Claude work — you don't need a push notification if you're already at your desk.

### How it works

1. Your shell writes a timestamp every time you run a command
2. The hook checks this timestamp before sending
3. If terminal was active within the threshold, notification is skipped

### Setup

**Step 1: Add to your shell config**

**Bash** (`~/.bashrc`):
```bash
PROMPT_COMMAND='date +%s > ~/.config/notify-ntfy/.last-active'
```

**Zsh** (`~/.zshrc`):
```zsh
precmd() { date +%s > ~/.config/notify-ntfy/.last-active }
```

**Fish** (`~/.config/fish/config.fish`):
```fish
function fish_prompt
    date +%s > ~/.config/notify-ntfy/.last-active
    # ... rest of your prompt
end
```

**Step 2: Configure threshold (optional)**

Default is 60 seconds. Set via environment variable:

```bash
export NTFY_ACTIVITY_THRESHOLD=300  # 5 minutes
```

Or disable entirely:

```bash
export NTFY_ACTIVITY_THRESHOLD=0  # Always notify
```

### Threshold behavior

| Activity | Result |
|----------|--------|
| Last command was 30s ago | Notification **skipped** (you're active) |
| Last command was 5m ago | Notification **sent** (you've stepped away) |
| No timestamp file exists | Notification **sent** (shell hook not set up) |
