# cGTD Quick Fixes — Design Spec

Date: 2026-05-06  
Source: `cgtd-issues-report (2).md`  
Scope: Quick wins (items 1–14 + item 19 from report table). Large features (timezone skill, email watermark, self-hosted Notion MCP) deferred to a separate cycle.

---

## Approach

Three logical commits, each independently reviewable and revertable:

1. `fix: skill patches` — all SKILL.md changes
2. `fix: infra` — docker-compose files + settings.json (both template and live)
3. `docs: setup improvements` — google-setup.md + README.md

---

## Commit 1: fix: skill patches

### skills/inbox-router/SKILL.md

| Change | Detail |
|--------|--------|
| Reaction emoji | Replace `📥` → `👍` in the "React" step (Telegram Bot API doesn't support `📥`) |
| `/cgtd` alias — pre-init guard | In the pre-init guard block, add `/cgtd` as an equivalent trigger for `/gtd-config` (so typing `/cgtd` before init routes to `gtd-interview`, not the "not configured" message) |
| `/cgtd` alias — post-init | In the post-init command dispatch table, add `/cgtd` as an alias for `/gtd-config` |
| Unknown command handler | If message starts with `/` and matches no known command, reply with a help text listing all available commands rather than silently routing to Inbox |
| Attachment copy-before-upload — `image_path` | When the `<channel>` tag has `image_path`: (1) `mkdir -p /root/.workspace-mcp/attachments`; (2) copy the file from `image_path` to `/root/.workspace-mcp/attachments/<basename>` (extract basename from `image_path`, do not hardcode path prefix); (3) call `create_drive_file` with the destination path; (4) delete the copy after upload. |
| Attachment copy-before-upload — `attachment_file_id` | Call `download_attachment` to get the local file path, then always apply the same mkdir+copy pattern: copy to `/root/.workspace-mcp/attachments/<basename>`, upload from there, delete the copy. This is simpler than runtime detection of allowed dirs and is always safe. |

**Note on Notion tool prefix:** Throughout all SKILL.md files, the correct tool prefix for Notion is `mcp__notion__` (matching the `"notion"` server key in `settings.json`). Do NOT use `mcp__plugin_Notion_notion__`, which appears in the Claude Code runtime's deferred tool list for a cloud-plugin variant.

### skills/proactive-inbox/SKILL.md

| Change | Detail |
|--------|--------|
| Notion date format | Document explicitly: use `"date:Date:start": "YYYY-MM-DD"` (not `"Date": "YYYY-MM-DD"`) for all `notion-create-pages` calls. Add example in the section that describes creating Notion entries. |
| Metadata-first Gmail strategy | Two-step fetch: (1) Call `search_gmail_messages` to get a list of message IDs, subjects, senders, and dates (this tool returns header-level data; no special format parameter needed). (2) Call `get_gmail_message_content` (or `get_gmail_messages_content_batch`) only for messages classified as potentially actionable in step 1. Batch size for step 2: max 10 messages per call. |
| Auth-fail behavior — replace existing rule | **Delete** the existing Failure modes rule «google-workspace returns `invalid_grant` for an account → log `fail` ... exit». **Replace** with: iterate over all accounts in `config.google.accounts[]`; if an account returns `invalid_grant`, ping Telegram «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`», skip that account, and continue with the remaining accounts. After all accounts are processed: if at least one account succeeded, log cron run as `degraded`; if all accounts failed, log `fail`. |
| Notion auth-fail behavior | If Notion MCP returns an auth error, ping Telegram «Notion auth истёк. Запусти `/cgtd-reauth notion`», skip all Notion writes, continue with Gmail/Calendar processing, log the run as `degraded`. |

### skills/cgtd-reauth/SKILL.md

Add a new section **"Если `/cgtd-reauth notion` не помогает"** after the existing Notion procedure. This section is **terminal/host-shell guidance** — make that explicit with a header or note:

> **Если после OAuth Notion всё ещё не работает (только с хостовой оболочки):**
>
> Notion MCP-сессия может зависнуть. Полный сброс:
> ```bash
> docker compose restart assistant
> docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
> ```
> Затем снова отправь `/cgtd-reauth notion` из Telegram.

### skills/gtd-interview/SKILL.md

In section 6.2 (interview an existing setup), **replace existing question 3** with three separate questions:

- **Question 3a — Projects DB:** «У тебя есть отдельная база для **Проектов** — многошаговых целей верхнего уровня (например "Построить дом", "Запустить продукт")? Если да — URL; если нет — `нет`.» Save ID into `config.notion.projects_id`. Set `config.gtd.has_projects_db: true/false`.
- **Question 3b — Tasks DB:** «У тебя есть отдельная база для **Задач** — конкретных шагов внутри проектов (например "Залить фундамент", "Подключить отопление")? Если да — URL; если нет — `нет`.» Save ID into `config.notion.tasks_id`. Set `config.gtd.has_tasks_db: true/false`. *(Note: a user may have Projects but no Tasks DB, Tasks but no Projects DB, both, or neither — all four combinations are valid.)*
- **Question 3c — Calendar integration:** «Как ты ведёшь расписание рядом с Next Actions? Выбери: `1)` Calendar и Next Actions — одна база (NA сразу идут в Календарь) `2)` раздельно — NA в Notion, встречи в Google Calendar `3)` не использую Calendar для планирования.» Save into `config.gtd.calendar_integration: "unified" | "separate" | "none"`.

Remaining questions 4–8 are renumbered to 6–10 accordingly.

**Config keys added:**
- `config.notion.projects_id` — Notion DB ID for Projects (null if none)
- `config.notion.tasks_id` — Notion DB ID for Tasks/steps (null if none)
- `config.gtd.has_projects_db` — boolean
- `config.gtd.has_tasks_db` — boolean
- `config.gtd.calendar_integration` — `"unified" | "separate" | "none"`

**In section 6.3 (generate skill overlay):** The overlay generator must account for all four Projects×Tasks combinations:

| has_projects_db | has_tasks_db | Overlay behavior |
|---|---|---|
| false | false | All multi-step work goes into Next Actions. Drop "move to Projects/Tasks" branches. |
| true | false | Multi-step goals → Projects DB. Steps are tracked as NA directly, not in a Tasks DB. |
| false | true | Tasks DB used for individual action steps. No Projects level. Route actionable items to Tasks or NA based on granularity. |
| true | true | Full hierarchy: Goals → Projects DB, Steps → Tasks DB, Atomic actions → Next Actions. |

For each existing skill that writes to Notion (proactive-inbox, morning-ritual, evening-review, process-inbox, inbox-router), the overlay must:
- Reference `config.notion.projects_id` and `config.notion.tasks_id` instead of hardcoded IDs only when the respective DB exists.
- Never silently drop a routing branch — if the target DB is absent, fall back to Next Actions and note in the Notion entry body that a more specific DB isn't configured.

**Calendar integration in skill overlays:**
- `"unified"`: morning-ritual should not create NA entries for items already in Google Calendar (they're the same system). Dedup by event_id. proactive-inbox: when creating NA for a deadline, note that it should also be added to Calendar.
- `"separate"`: morning-ritual shows Calendar and NA as two parallel sections. proactive-inbox creates NA entries independently of Calendar.
- `"none"`: Calendar section omitted from morning-ritual and evening-review.

If a config flag is `true` but the corresponding `_id` is null (URL validation failed during interview), the overlay should emit a warning in Telegram on first run: «Настроена база [Projects/Tasks] но ID не найден — проверь `/gtd-config`.» rather than silently routing to a fallback.

### skills/init/SKILL.md

Add a **Pre-flight MCP check** step at the end of Phase 1 (terminal session), immediately before the "✓ Bootstrap done" message.

**Google check:** Call `mcp__google-workspace__list_calendars` with any placeholder email. Two expected outcomes:
- Returns an OAuth URL → expected, everything is working, do not warn.
- Returns a tool execution error (MCP connection failed, command not found, non-200 from the server) → print: «⚠ google-workspace MCP is not responding. Check `data/claude-home/settings.json` and run `docker compose restart`.»

**Notion check:** Call `mcp__notion__notion-search` with an empty query. Two expected outcomes:
- Returns an OAuth URL (or a valid response) → expected, do not warn.
- Returns a tool execution error (network failure, MCP server unreachable, non-200 status that is not a redirect) → print: «⚠ Notion MCP is not responding. Check `data/claude-home/settings.json`.»

The distinction: an OAuth URL in the response body means the server is reachable and responding correctly; a tool-layer exception or error code means the server is misconfigured or unreachable. Do not warn on auth-not-yet-set — that is the normal state at Phase 1 end.

This check is terminal-only. It is not repeated during the Telegram interview.

---

## Commit 2: fix: infra

### docker-compose.yml

Add to `environment` for **both** services (`assistant` and `assistant_user2`):

```yaml
- ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

### docker-compose.example.yml

Add to `environment` for **both** services (`work` and `personal`):

```yaml
- ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

### .claude/settings.json.example

Add a `permissions` section using the same wildcard syntax as the live file (`Bash*`, no parentheses):

```json
{
  "permissions": {
    "allow": [
      "Bash*",
      "Read*",
      "Write*",
      "mcp__google-workspace__*",
      "mcp__notion__*",
      "mcp__plugin_telegram_telegram__*"
    ]
  },
  "mcpServers": { ... }
}
```

### data/claude-home/settings.json (live install)

Extend the existing `permissions.allow` array (currently only `"Bash*"`) with:

```json
"allow": [
  "Bash*",
  "Read*",
  "Write*",
  "mcp__google-workspace__*",
  "mcp__notion__*",
  "mcp__plugin_telegram_telegram__*"
]
```

Do not touch `mcpServers` or `enabledPlugins`.

---

## Commit 3: docs: setup improvements

### docs/google-setup.md

**Change 1 — Redirect URI checkpoint (step 4):**  
After the existing "Authorized redirect URI: `http://localhost:8000/oauth2callback`" line in step 4, add a callout:

> **⚠ Critical:** The redirect URI must be exactly `http://localhost:8000/oauth2callback`. A missing or mis-typed URI is the most common cause of OAuth failures. Double-check it in the console before clicking Create.

**Change 2 — Production vs Testing (existing section):**  
Expand "Avoiding the 7-day refresh-token expiry" to explicitly clarify:
- «Publish to Production» does NOT make the app publicly discoverable or listed in any Google directory
- No Google verification required for personal use (verification is only required to remove the «unverified app» warning for end users of public apps)
- The «unverified app» warning during OAuth is normal — click «Advanced → Go to app (unsafe)»
- After publishing, refresh tokens last indefinitely (until revoked, scope-changed, or 6 months of inactivity)

### README.md

**Change 1 — Fix `$EDITOR .env`:**  
Replace `$EDITOR .env` with `nano .env  # or: vim .env`

**Change 2 — Add `cd cgtd` to step 1:**  
Add `cd cgtd` as an explicit line after `git clone` in step 1.

**Change 3 — MCP note in step 2 (terminal bootstrap):**  
After the `/init-cgtd` description in step 2, add:
> The bootstrap includes a quick MCP connectivity check. If Google or Notion MCPs aren't reachable, you'll see a warning in the terminal — fix `data/claude-home/settings.json` and run `docker compose restart` before proceeding.

---

## Files Changed

| File | Commit |
|------|--------|
| `skills/inbox-router/SKILL.md` | 1 |
| `skills/proactive-inbox/SKILL.md` | 1 |
| `skills/cgtd-reauth/SKILL.md` | 1 |
| `skills/gtd-interview/SKILL.md` | 1 |
| `skills/init/SKILL.md` | 1 |
| `docker-compose.yml` | 2 |
| `docker-compose.example.yml` | 2 |
| `.claude/settings.json.example` | 2 |
| `data/claude-home/settings.json` | 2 |
| `docs/google-setup.md` | 3 |
| `README.md` | 3 |

---

## Out of Scope (deferred)

- `cgtd-timezone` skill — timezone management command
- Email watermark (`/data/email-watermarks.json`) — dedup by last seen message_id
- Self-hosted Notion MCP migration
- Cron persistence across session restarts (`entrypoint.sh` pre-seeding)
