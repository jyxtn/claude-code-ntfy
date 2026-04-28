# Configuration Guide

Configuration for `notify-ntfy.sh` can be provided via environment variables or a config file.

## Resolution Order

Configuration is resolved in this priority (highest wins):

1. **Environment variables** (`NTFY_TOPIC`, `NTFY_SERVER_URL`, `NTFY_TOKEN`)
2. **Config file** (`~/.config/notify-ntfy/config.json`)
3. **Defaults** (only `server_url` has a default; `topic` is required)

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
