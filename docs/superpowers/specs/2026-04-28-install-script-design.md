# install.sh Design Spec

Interactive CLI installer for notify-ntfy with global and experimental local modes.

## Scope

Single script (`install.sh`) with guided setup for ntfy notifications.

## Components

| File | Purpose |
|------|---------|
| `install.sh` | Main interactive installer (global + experimental local) |
| `uninstall.sh` | Removes hooks and config |
| `words.txt` | Embedded word list (adjectives + nouns) |

## Installation Modes

### Global Mode (default)
- Installs to `~/.claude/hooks/notify-ntfy.sh`
- Modifies `~/.claude/settings.json`
- Affects all Claude Code sessions

### Local Mode (`--local` flag)
- Installs to `.claude/hooks/notify-ntfy.sh` (project directory)
- **WARNING:** Experimental — Claude Code's hook loading from project-local configs is not fully supported
- Adds hook config to `CLAUDE.md` or local `.claude/settings.json` if possible

## Flow

```
install.sh [--local]
  ↓
Check deps (curl, jq)
  ↓ [if jq missing]
Offer to install jq (brew/apt)
  ↓
Detect existing config → show → ask: overwrite / skip / abort
  ↓
Choose server:
  [1] ntfy.sh (public) ← default
  [2] Self-hosted
    ↓ [if 2]
  Prompt for URL
    ↓ [if 1]
  Generate 3 topic options from words.txt
  Show options:
    1) brisk-ocean-cloud
    2) golden-forest-river
    3) swift-mountain-wind
    4) [Enter your own]
  User selects
  ↓
Create ~/.config/notify-ntfy/config.json
  ↓
Copy hooks/notify-ntfy.sh → target
  ↓
Show settings.json diff
Ask: proceed / skip / abort
  ↓ [if proceed]
Backup settings.json → ~/.claude/settings.json.backup.<timestamp>
Apply changes
  ↓
Send test notification
Report success / failure
```

## Configuration

### Global Mode Paths
- Config: `~/.config/notify-ntfy/config.json`
- Hook: `~/.claude/hooks/notify-ntfy.sh`
- Settings: `~/.claude/settings.json`

### Local Mode Paths
- Config: `.claude/notify-ntfy-config.json` (project-local override)
- Hook: `.claude/hooks/notify-ntfy.sh`
- Settings: `.claude/settings.json` (or warns to add to CLAUDE.md)

## Word List

Uses EFF-style wordlist:
- ~150 common adjectives (blue, swift, golden, brisk, etc.)
- ~150 common nouns (ocean, forest, mountain, cloud, river, wind, etc.)
- Format: `adjective-noun-noun` (e.g., "golden-forest-river")
- Embedded in `words.txt`, not hardcoded in script

## Error Handling

- Check jq installed → offer auto-install → abort if declined
- Validate JSON before writing (use jq to verify)
- Backup settings.json before modification
- Clear error messages at each failure point
- Test notification at end — report curl exit code

## uninstall.sh

```
uninstall.sh [--local]
  ↓
Detect existing install
  ↓
Remove hook script
Remove config file
Remove settings.json entries (with backup)
  ↓
Confirm removal
```

## Notes

- **Other harnesses (OpenCode, etc.):** Phase 2+ — each has different extension mechanisms
- Bash 3.2 compatible: no associative arrays, no `[[ ]]` regex matching
- No external deps beyond curl/jq
