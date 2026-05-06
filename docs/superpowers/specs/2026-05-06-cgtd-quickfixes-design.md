# cGTD Quick Fixes — Design Spec

Date: 2026-05-06  
Source: `cgtd-issues-report (2).md`  
Scope: Quick wins (items 1–14 + item 19 from report table). Large features (timezone skill, email watermark, self-hosted Notion MCP) deferred to a separate cycle.

---

## Approach

Three logical commits, each independently reviewable and revertable:

1. `fix: skill patches` — all SKILL.md changes
2. `fix: infra` — docker-compose + settings.json (both template and live)
3. `docs: setup improvements` — google-setup.md + README.md

---

## Commit 1: fix: skill patches

### skills/inbox-router/SKILL.md

| Change | Detail |
|--------|--------|
| Reaction emoji | Replace `📥` → `👍` in the "React" step (Telegram Bot API doesn't allow `📥`) |
| `/cgtd` alias | Treat `/cgtd` as equivalent to `/gtd-config` in the command dispatch table |
| Unknown command handler | If message starts with `/` and matches no known command, reply with a help text listing all available commands rather than silently routing to Inbox |
| Attachment copy-before-upload | Before calling `create_drive_file`, copy the file from `/root/.claude/channels/telegram/inbox/<filename>` to `/root/.workspace-mcp/attachments/<filename>` via Bash, then upload from the new path, then delete the copy |

**Why copy-before-upload:** `workspace-mcp` restricts readable paths to `ALLOWED_FILE_DIRS`. Even after adding the env var (commit 2), this belt-and-suspenders copy ensures the skill works on existing containers that haven't been restarted yet.

### skills/proactive-inbox/SKILL.md

| Change | Detail |
|--------|--------|
| Notion date format | Document explicitly: use `"date:Date:start": "YYYY-MM-DD"` (not `"Date": "YYYY-MM-DD"`) for all Notion create-pages calls. Add example in the "Sources" → "routing" section. |
| Metadata-first Gmail strategy | Fetch all messages with `format: "metadata"` first (Subject/From/Date only). Then fetch `format: "full"` only for messages classified as potentially actionable. Batch size: 10, not 20. |
| Degraded status on partial auth failure | If one Google account returns `invalid_grant` but at least one other account succeeds, mark cron run as `degraded` (not `fail`). Still ping Telegram about the failing account. |
| Unified auth-fail handler | Any `invalid_grant` from any account → immediate Telegram ping «Auth истёк для `<account>`. Запусти `/cgtd-reauth <service> <id>`» → log + exit cleanly. Consistent across all failure paths. |

### skills/cgtd-reauth/SKILL.md

Add a new section **"Если `/cgtd-reauth notion` не помогает"** after the existing Notion procedure:

> If `notion-search` still returns an auth error after the OAuth flow, the Notion MCP session may be stuck. Full reset:
> ```bash
> docker compose restart assistant
> docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
> ```
> Then retry `/cgtd-reauth notion` from Telegram.

### skills/gtd-interview/SKILL.md

In section 6.2 (interview an existing setup), add two questions after the existing database URL questions:

- **Question on Projects:** «У тебя есть отдельная база для многошаговых целей / проектов (Projects) — отдельно от атомарных Next Actions? Если да — URL, если нет — напиши `нет`.»
- **Question on Calendar integration:** «Как Календарь соотносится с Next Actions — ты планируешь NA в Календаре или ведёшь их отдельно?»

Save answers into `config.gtd.has_projects_db` (bool) and `config.gtd.calendar_integration` (string: `"calendar"` / `"separate"` / `"none"`). Reference in skill overlays where relevant.

### skills/init/SKILL.md

Add a **Pre-flight MCP check** step before handing off to `gtd-interview`. After Phase 1 bootstrap and before printing the "open Telegram" message, verify:

1. Call `mcp__google-workspace__list_calendars` with any email → if fails with connection error (not auth error), warn: «google-workspace MCP недоступен. Проверь `settings.json` и перезапусти контейнер.»
2. Call `mcp__notion__notion-search` with empty query → if fails with connection error, warn: «Notion MCP недоступен. Проверь подключение в `settings.json`.»

Auth errors (OAuth URL returned) are expected at this stage — don't flag them. Only flag hard connection failures.

---

## Commit 2: fix: infra

### docker-compose.yml

Add to `environment` for **both** services (`assistant` and `assistant_user2`):

```yaml
- ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

### .claude/settings.json.example

Add a `permissions` section alongside the existing `mcpServers`:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "mcp__google-workspace__*",
      "mcp__notion__*",
      "mcp__plugin_telegram_telegram__*"
    ]
  },
  "mcpServers": { ... }
}
```

### data/claude-home/settings.json (live install)

Same `permissions` block added to the existing file (which already has a populated `mcpServers` section).

---

## Commit 3: docs: setup improvements

### docs/google-setup.md

**Change 1 — Redirect URI checkpoint (step 4):**  
Add a callout box immediately after the "Authorized redirect URI" line in step 4:

> **⚠ Critical:** The redirect URI must be exactly `http://localhost:8000/oauth2callback`. A missing or mis-typed URI is the most common cause of OAuth failures. Double-check it in the console before clicking Create.

**Change 2 — Production vs Testing (existing section):**  
Expand "Avoiding the 7-day refresh-token expiry" to clarify:
- «Publish to Production» does NOT make the app publicly discoverable
- No Google verification required for personal use (only needed for public apps)
- The «unverified app» warning during OAuth is normal — click «Advanced → Go to app (unsafe)»
- After publishing, refresh tokens last indefinitely

### README.md

**Change 1 — Fix `$EDITOR .env`:**  
Replace `$EDITOR .env` with `nano .env  # or: vim .env`

**Change 2 — Add `cd cgtd` to step 1:**  
Add `cd cgtd` as an explicit line after `git clone` in step 1.

**Change 3 — MCP note before `/gtd-config`:**  
In step 4 ("Telegram chat — finish setup"), add a note:
> Before sending `/gtd-config`, confirm Google and Notion MCPs are connected (the `/init-cgtd` pre-flight check will tell you if they aren't).

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
