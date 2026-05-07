# Notion MCP Migration: Cloud OAuth → Self-Hosted API Key

Date: 2026-05-07  
Scope: Replace the cloud-hosted Notion MCP (`mcp.notion.com/mcp`) with the self-hosted `@notionhq/notion-mcp-server` npm package. Per-container isolation via Internal Integration Token. Full tool-name migration across all skill files.

---

## Problem

The current Notion MCP uses `mcp.notion.com/mcp` (HTTP transport, OAuth). The OAuth token is tied to the Claude.ai cloud account, not to the local container. When multiple containers run under the same Claude.ai account, they share a single Notion workspace — making per-user or per-project isolation impossible.

## Solution

Replace with `@notionhq/notion-mcp-server` v2.1.0 (stdio transport, Internal Integration Token). Data still lives in Notion's cloud; only the authentication mechanism changes: each container uses its own `NOTION_API_KEY`, stored in `.env` or entered during the Telegram interview.

The npm package is run via `npx -y @notionhq/notion-mcp-server`. No Dockerfile change required — `npx -y` downloads on first use and caches in the npm global cache (in the container's writable layer, so survives restarts but not image rebuilds). This is an accepted tradeoff: a short download delay after `docker compose up --build`.

---

## Tool Name Mapping

The MCP server key in `settings.json` remains `"notion"`, so the `mcp__notion__` prefix is unchanged. The `mcp__notion__*` wildcard in permissions covers all new tool names without modification.

| Old tool (cloud MCP) | New tool (`@notionhq/notion-mcp-server`) |
|---|---|
| `mcp__notion__notion-search` | `mcp__notion__search` |
| `mcp__notion__notion-create-pages` | `mcp__notion__create-a-page` |
| `mcp__notion__notion-update-page` | `mcp__notion__update-a-page` |
| `mcp__notion__notion-fetch` | `mcp__notion__retrieve-a-page` |
| `mcp__notion__notion-query-database-view` | `mcp__notion__query-data-source` |
| `mcp__notion__notion-move-pages` | `mcp__notion__move-page` |

---

## Section 1: Infrastructure

### `.claude/settings.json.example`

Replace the existing `notion` MCP entry:

**Before:**
```json
"notion": {
  "type": "http",
  "url": "https://mcp.notion.com/mcp"
}
```

**After:**
```json
"notion": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@notionhq/notion-mcp-server"],
  "env": {
    "NOTION_API_KEY": "${NOTION_API_KEY}"
  }
}
```

### `.env.example`

Add after the Google OAuth block:

```
# Notion Internal Integration Token — optional if set during /gtd-config
# Create at: notion.so → Settings → Connections → Develop or manage integrations
NOTION_API_KEY=
```

### `docker-compose.yml` and `docker-compose.example.yml`

Add to the `environment:` block for all services (same pattern as `TZ` and `ALLOWED_FILE_DIRS`):

```yaml
- NOTION_API_KEY=${NOTION_API_KEY:-}
```

The `:-` default prevents docker-compose from erroring when the variable is absent (user is providing it via gtd-interview instead).

### `entrypoint.sh`

Two additions, both before the final `exec "$@"` line:

**1. Resolve NOTION_API_KEY** (after the TZ drift warning block added earlier):

```bash
# Resolve NOTION_API_KEY: prefer env var, fall back to config.json
if [ -z "${NOTION_API_KEY:-}" ] && [ -f "$DATA/config.json" ]; then
  cfg_notion_key=$(jq -r '.notion.api_key // empty' "$DATA/config.json" 2>/dev/null)
  if [ -n "$cfg_notion_key" ]; then
    export NOTION_API_KEY="$cfg_notion_key"
  fi
fi
```

(`jq` is already used in entrypoint.sh — pre-existing dependency, not new.)

**2. Migrate existing settings.json** (before the NOTION_API_KEY resolution block):

Existing installs have a `data/claude-home/settings.json` that will NOT be auto-regenerated (the copy only runs when the file is absent). Update the `notion` MCP config in-place on startup:

```bash
# Migrate Notion MCP from HTTP to stdio if needed
if [ -f "$DATA/claude-home/settings.json" ]; then
  notion_type=$(jq -r '.mcpServers.notion.type // empty' "$DATA/claude-home/settings.json" 2>/dev/null)
  if [ "$notion_type" = "http" ]; then
    # Note: "${NOTION_API_KEY}" is a literal string here — bash single-quotes prevent expansion.
    # Claude Code performs its own ${VAR} substitution when reading settings.json at startup.
    jq '.mcpServers.notion = {"type":"stdio","command":"npx","args":["-y","@notionhq/notion-mcp-server"],"env":{"NOTION_API_KEY":"${NOTION_API_KEY}"}}' \
      "$DATA/claude-home/settings.json" > "$DATA/claude-home/settings.json.tmp" && \
      mv "$DATA/claude-home/settings.json.tmp" "$DATA/claude-home/settings.json" || \
      rm -f "$DATA/claude-home/settings.json.tmp"
    echo "✓ Notion MCP migrated to stdio in settings.json"
  fi
fi
```

This runs once per existing install (the `notion_type = "http"` guard ensures it is idempotent).

---

## Section 2: Setup Flow

### `skills/gtd-interview/SKILL.md` — Section 4 (Notion auth)

The current file calls this **Section 4** ("Notion OAuth"). Replace the entire OAuth flow with:

1. Call `mcp__notion__search query=""`.
   - If it returns valid results or an empty list → key already configured (came from `.env`). Continue to Section 5 (Drive folder).
   - If it returns an error (MCP not connected / key missing) → proceed to step 2.

2. Send Telegram message:
   > Нужен Notion Internal Integration Token:
   > 1. Открой notion.so → Settings → Connections → Develop or manage integrations → New integration
   > 2. Type: **Internal**. Название — любое (например `cgtd`).
   > 3. Скопируй **Internal Integration Token** (начинается с `secret_...`) и пришли сюда.

3. When user sends the token:
   - Validate format: must start with `secret_`. If invalid, ask again.
   - Save to `config_draft.notion.api_key` and write to `/data/config.json`.
   - Advance `init-progress.json` `section` to `"drive_folder"`. No new enum value needed — this skips past the old `notion_oauth` section entirely so the next resume starts at Section 5 (Drive folder) without re-entering the API key flow.

4. Reply:
   > ✓ Токен сохранён. Нужен перезапуск контейнера чтобы он подхватился:
   > ```
   > docker compose restart assistant
   > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
   > ```
   > После перезапуска напиши `/gtd-config` — продолжим с настройки баз данных Notion.

5. On next `/gtd-config` invocation: state machine loads `section = "drive_folder"` and resumes there. At the top of the `drive_folder` handler, call `mcp__notion__search query=""` to verify connectivity. If it fails, tell the user the key isn't working and prompt them to check `.env` / restart again. If it succeeds, proceed normally.

**Important:** Also update all tool-name references within `gtd-interview/SKILL.md` per the mapping table above.

### `skills/cgtd-reauth/SKILL.md` — `/cgtd-reauth notion`

Replace the OAuth-based flow with API key update. Keep the container restart guidance (still valid for stdio MCP):

1. Send Telegram:
   > Пришли новый Notion Internal Integration Token (начинается с `secret_...`).
2. Validate (must start with `secret_`). Save to `config.notion.api_key`.
3. Reply:
   > ✓ Токен обновлён. Перезапусти контейнер чтобы применить:
   > ```
   > docker compose restart assistant
   > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
   > ```
   > После перезапуска Notion MCP подхватит новый токен автоматически.

Replace only the OAuth-specific procedure (lines 31–36: clearing cached OAuth token, `claude mcp remove notion`, OAuth URL flow). Keep the existing "Если `/cgtd-reauth notion` не помогает (только с хостовой оболочки)" block (currently lines 37–46) — its container restart instructions remain valid for stdio MCP (a hung npx process also needs a restart to recover).

---

## Section 3: Tool Name Migration (per file)

**`skills/inbox-router/SKILL.md`**
- `mcp__notion__notion-create-pages` → `mcp__notion__create-a-page`
- `mcp__notion__notion-update-page` → `mcp__notion__update-a-page`

**`skills/proactive-inbox/SKILL.md`**
- `mcp__notion__notion-search` → `mcp__notion__search` (2 occurrences)

(Note: `notion-create-pages` does NOT appear in this file — no change needed for creates.)

**`skills/process-inbox/SKILL.md`**
- `mcp__notion__notion-query-database-view` → `mcp__notion__query-data-source`
- `mcp__notion__notion-search` → `mcp__notion__search` (3 occurrences: step 1 fallback, dedup section, inline text)
- `mcp__notion__notion-create-pages` → `mcp__notion__create-a-page`
- `mcp__notion__notion-move-pages` → `mcp__notion__move-page` (archive step)

**`skills/morning-ritual/SKILL.md`**
- `mcp__notion__notion-update-page` → `mcp__notion__update-a-page`

**`skills/evening-review/SKILL.md`**
- `mcp__notion__notion-search` → `mcp__notion__search`
- `mcp__notion__notion-update-page` → `mcp__notion__update-a-page`

**`skills/gtd-interview/SKILL.md`**
- `mcp__notion__notion-search` → `mcp__notion__search`
- `mcp__notion__notion-fetch` → `mcp__notion__retrieve-a-page`
- `mcp__notion__notion-create-pages` → `mcp__notion__create-a-page`

**`skills/init/SKILL.md`**
- `mcp__notion__notion-search` → `mcp__notion__search`

**`skills/cgtd-reauth/SKILL.md`**
- `mcp__notion__notion-search` → `mcp__notion__search`

---

## Files Changed

| File | Change |
|------|--------|
| `.claude/settings.json.example` | Replace cloud HTTP MCP with stdio + API key |
| `.env.example` | Add `NOTION_API_KEY=` |
| `docker-compose.yml` | Add `NOTION_API_KEY` env passthrough |
| `docker-compose.example.yml` | Add `NOTION_API_KEY` env passthrough |
| `entrypoint.sh` | Auto-migrate existing settings.json; resolve NOTION_API_KEY from config fallback |
| `skills/gtd-interview/SKILL.md` | Replace OAuth flow (Section 4) with API key flow; tool name updates |
| `skills/cgtd-reauth/SKILL.md` | Replace OAuth reauth with API key update; tool name updates |
| `skills/inbox-router/SKILL.md` | Tool name updates |
| `skills/proactive-inbox/SKILL.md` | Tool name updates |
| `skills/process-inbox/SKILL.md` | Tool name updates + move-page |
| `skills/morning-ritual/SKILL.md` | Tool name updates |
| `skills/evening-review/SKILL.md` | Tool name updates |
| `skills/init/SKILL.md` | Tool name updates |

All changes in one commit: `feat: migrate Notion MCP to self-hosted API key`.
