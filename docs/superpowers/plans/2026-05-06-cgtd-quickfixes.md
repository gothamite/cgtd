# cGTD Quick Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply 11 targeted fixes to skills, infra config, and docs based on issues found in the cGTD session report (2026-05-06).

**Architecture:** Three logical commits — (1) SKILL.md patches for 5 skills, (2) docker-compose + settings.json infra, (3) docs. All edits are to Markdown, YAML, or JSON files; no executable code is changed. No test suite exists for skills — verification is done by grepping for expected strings after each edit.

**Tech Stack:** Bash (grep/sed for verification), git. Skills are plain Markdown. Config is JSON/YAML.

**Spec:** `docs/superpowers/specs/2026-05-06-cgtd-quickfixes-design.md`

---

## File Map

| File | Task | Change type |
|------|------|-------------|
| `skills/inbox-router/SKILL.md` | 1 | Modify |
| `skills/proactive-inbox/SKILL.md` | 2 | Modify |
| `skills/cgtd-reauth/SKILL.md` | 3 | Modify |
| `skills/gtd-interview/SKILL.md` | 4 | Modify |
| `skills/init/SKILL.md` | 5 | Modify |
| `docker-compose.yml` | 6 | Modify |
| `docker-compose.example.yml` | 6 | Modify |
| `.claude/settings.json.example` | 7 | Modify |
| `data/claude-home/settings.json` | 7 | Modify |
| `docs/google-setup.md` | 8 | Modify |
| `README.md` | 9 | Modify |

---

## Task 1: inbox-router/SKILL.md — five targeted edits

**Files:**
- Modify: `skills/inbox-router/SKILL.md`

The file currently (lines 14-15): pre-init guard checks `/gtd-config` only. Line 26: post-init commands list. Line 46: `📥` react. Line 37–40: attachment upload section. The file has no unknown-command handler.

### 1a — Replace `📥` reaction with `👍`

- [ ] **Open the file and find the React line**

```bash
grep -n "📥" skills/inbox-router/SKILL.md
```

Expected: one match around line 46: `6. React with \`📥\``

- [ ] **Apply the edit**

In `skills/inbox-router/SKILL.md`, replace:
```
6. React with `📥` via `mcp__plugin_telegram_telegram__react`. No reply text.
```
with:
```
6. React with `👍` via `mcp__plugin_telegram_telegram__react`. No reply text.
```

- [ ] **Verify**

```bash
grep "react" skills/inbox-router/SKILL.md
```

Expected: line contains `👍`, no `📥`.

---

### 1b — Add `/cgtd` alias to pre-init guard

- [ ] **Find the pre-init guard block**

```bash
grep -n "gtd-config\|cgtd" skills/inbox-router/SKILL.md | head -20
```

- [ ] **Apply the edit**

In the pre-init guard section, replace:
```
- If the message is `/gtd-config` (case-insensitive) → invoke `gtd-interview` skill.
```
with:
```
- If the message is `/gtd-config` or `/cgtd` (case-insensitive) → invoke `gtd-interview` skill.
```

- [ ] **Verify**

```bash
grep "cgtd\|gtd-config" skills/inbox-router/SKILL.md
```

Expected: pre-init line now mentions both `/gtd-config` and `/cgtd`.

---

### 1c — Add `/cgtd` alias to post-init command table

- [ ] **Find the post-init commands section**

```bash
grep -n "^\- \`/gtd-config\`" skills/inbox-router/SKILL.md
```

- [ ] **Apply the edit**

Replace:
```
- `/gtd-config` → invoke `gtd-interview` (reconfigure menu)
```
with:
```
- `/gtd-config` or `/cgtd` → invoke `gtd-interview` (reconfigure menu)
```

- [ ] **Verify**

```bash
grep "/cgtd" skills/inbox-router/SKILL.md | wc -l
```

Expected: at least 2 lines (pre-init guard + post-init table).

---

### 1d — Add unknown command handler

- [ ] **Find the section boundary between commands and routing logic**

```bash
grep -n "doesn't start with" skills/inbox-router/SKILL.md
```

- [ ] **Apply the edit**

Replace:
```
If the message doesn't start with `/`, route to Inbox per the logic below.
```
with:
```
If the message doesn't start with `/`, route to Inbox per the logic below.

If the message starts with `/` but matches none of the commands above, reply with a help text:

> Неизвестная команда. Доступные команды:
> `/gtd-config` или `/cgtd` — настройка
> `/cgtd-reauth google <email>` — переавторизация Google
> `/cgtd-reauth notion` — переавторизация Notion
> `/morning` / `/утро` — утренний брифинг
> `/evening` / `/вечер` — вечерний обзор
> `/inbox` / `/разбери` — обработка Inbox
> `/status` — статус cron-задач
>
> Обычное сообщение (без `/`) → попадает в Notion Inbox.

Do NOT route unknown commands to Inbox.
```

- [ ] **Verify**

```bash
grep -c "Неизвестная команда\|unknown" skills/inbox-router/SKILL.md
```

Expected: ≥ 1.

---

### 1e — Add attachment copy-before-upload logic

- [ ] **Find the existing attachment section**

```bash
grep -n "Attachments\|image_path\|attachment_file_id\|create_drive_file" skills/inbox-router/SKILL.md
```

- [ ] **Apply the edit**

In the routing logic section, replace the existing attachment step (step 3):
```
3. **Attachments**: if the message has an `image_path` or `attachment_file_id`:
   - Download via `mcp__plugin_telegram_telegram__download_attachment`.
   - Upload to the primary Drive folder via `mcp__google-workspace__create_drive_file user_google_email=<config.google.primary> folder_id=<config.google.drive_inbox_folder_id>`.
   - Get the shareable link.
```
with:
```
3. **Attachments**: if the message has an `image_path` or `attachment_file_id`:
   - **For `image_path`**: the file path is given directly in the channel tag attribute.
     1. Run `mkdir -p /root/.workspace-mcp/attachments` via Bash.
     2. Copy the file: `cp <image_path> /root/.workspace-mcp/attachments/<basename>` via Bash (extract basename from the path).
     3. Upload via `mcp__google-workspace__create_drive_file user_google_email=<config.google.primary> folder_id=<config.google.drive_inbox_folder_id> fileUrl=file:///root/.workspace-mcp/attachments/<basename>`.
     4. Delete the copy: `rm /root/.workspace-mcp/attachments/<basename>` via Bash.
   - **For `attachment_file_id`**: call `mcp__plugin_telegram_telegram__download_attachment` to get the local path, then apply the same mkdir+copy+upload+delete pattern using that path.
   - Get the shareable link via `mcp__google-workspace__get_drive_shareable_link` after upload.
   - If Drive upload fails for any reason: still create the Inbox entry, include `(вложение не удалось загрузить)` in the body.
```

- [ ] **Verify**

```bash
grep -n "workspace-mcp/attachments\|mkdir -p" skills/inbox-router/SKILL.md
```

Expected: lines describing the copy step.

---

### 1f — Commit

- [ ] **Stage and commit**

```bash
git add skills/inbox-router/SKILL.md
git commit -m "fix: inbox-router — 👍 reaction, /cgtd alias, unknown cmd help, attachment copy-before-upload"
```

---

## Task 2: proactive-inbox/SKILL.md — three targeted edits

**Files:**
- Modify: `skills/proactive-inbox/SKILL.md`

### 2a — Document Notion date format

- [ ] **Find the section that creates Notion entries**

```bash
grep -n "notion-create-pages\|create.*NA\|Next Actions.*Date\|Date.*start" skills/proactive-inbox/SKILL.md
```

- [ ] **Apply the edit**

In the Gmail classification section (or wherever Notion create calls are described), add a note directly before or after the first mention of creating a Next Actions entry:

```
**Notion date format:** When creating pages with a Date property, always use the expanded key format:
- `"date:Date:start": "YYYY-MM-DD"` (required)
- `"date:Date:end": "YYYY-MM-DD"` (optional, for ranges such as hotel stays)
Do NOT use `"Date": "YYYY-MM-DD"` — this causes a validation error.
```

- [ ] **Verify**

```bash
grep "date:Date:start" skills/proactive-inbox/SKILL.md
```

Expected: 1 match.

---

### 2b — Replace Gmail fetch strategy with metadata-first two-step

- [ ] **Find the current Gmail source description**

```bash
grep -n "search_gmail_messages\|Gmail primary\|Gmail promo" skills/proactive-inbox/SKILL.md | head -10
```

- [ ] **Apply the edit**

In the "Sources" section, replace the Gmail fetch description. Find:
```
- Gmail primary: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h -category:promotions -category:social"`. Includes read mail.
- Gmail promo sweep: same tool, `query="newer_than:24h category:promotions"`. See "Promo deadline scan" below.
```
and replace with:
```
- **Gmail primary (two-step fetch):**
  1. **Header scan**: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h -category:promotions -category:social"`. This returns message IDs, subjects, senders, and dates — enough to classify.
  2. **Full content fetch**: call `mcp__google-workspace__get_gmail_message_content` (or `get_gmail_messages_content_batch`) with `format: "full"` **only** for messages classified as potentially actionable from step 1. Fetch in batches of **max 10** messages per call.
- **Gmail promo sweep**: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h category:promotions"`. Header scan only; fetch full content only for promos that pass the deadline keyword check.
```

- [ ] **Verify**

```bash
grep -n "Header scan\|two-step\|max 10" skills/proactive-inbox/SKILL.md
```

Expected: all three strings present.

---

### 2c — Replace auth-fail behavior (degraded mode)

- [ ] **Find the existing failure modes section**

```bash
grep -n "invalid_grant\|fail.*google_auth\|exit" skills/proactive-inbox/SKILL.md
```

Expected: current line ~101: `google-workspace returns \`invalid_grant\` for an account → log \`fail\` with \`google_auth_expired:<email>\`, send Telegram …, exit.`

- [ ] **Apply the edit**

In the `## Failure modes` section, **replace** the `invalid_grant` rule (the entire bullet point that says log `fail` and exit):
```
- google-workspace returns `invalid_grant` for an account → log `fail` with `google_auth_expired:<email>`, send Telegram «Google auth for <email> expired, run `/cgtd-reauth <email>`», exit. See `cgtd-reauth/SKILL.md`.
```
with:
```
- **Per-account Google auth failure**: if one account returns `invalid_grant`, do NOT exit. Instead:
  1. Send Telegram: «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`».
  2. Skip that account, continue processing remaining accounts in `config.google.accounts[]`.
  3. After all accounts are processed: if at least one account succeeded → log cron run as `degraded` (not `fail`). If all accounts failed → log `fail`.
- **Notion auth failure**: if Notion MCP returns an auth error → send Telegram «Notion auth истёк. Запусти `/cgtd-reauth notion`». Skip all Notion writes. Continue Gmail/Calendar processing. Log as `degraded`.
```

- [ ] **Verify**

```bash
grep -n "degraded\|per-account\|Skip that account" skills/proactive-inbox/SKILL.md
```

Expected: all three strings present. Also verify old "exit" rule is gone:

```bash
grep "log \`fail\` with \`google_auth_expired" skills/proactive-inbox/SKILL.md
```

Expected: no output (old rule removed).

---

### 2d — Commit

- [ ] **Stage and commit**

```bash
git add skills/proactive-inbox/SKILL.md
git commit -m "fix: proactive-inbox — Notion date format, metadata-first Gmail, degraded auth mode"
```

---

## Task 3: cgtd-reauth/SKILL.md — add Notion stuck-session recovery

**Files:**
- Modify: `skills/cgtd-reauth/SKILL.md`

- [ ] **Find the end of the Notion procedure section**

```bash
grep -n "Procedure.*Notion\|Wait for.*done.*Retry\|✓ Notion reauthorized" skills/cgtd-reauth/SKILL.md
```

- [ ] **Apply the edit**

After the existing `## Procedure — Notion` section (after the line «Wait for «done». Retry. On success → reply «✓ Notion reauthorized».»), add a new subsection:

```markdown

### Если `/cgtd-reauth notion` не помогает (только с хостовой оболочки)

Если после OAuth Notion MCP всё ещё возвращает ошибку авторизации, сессия MCP может зависнуть. Полный сброс запускается **из терминала на хосте** (не из Telegram):

```bash
docker compose restart assistant
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

После перезапуска отправь `/cgtd-reauth notion` из Telegram ещё раз.
```

- [ ] **Verify**

```bash
grep -n "не помогает\|docker compose restart" skills/cgtd-reauth/SKILL.md
```

Expected: both strings present.

- [ ] **Commit**

```bash
git add skills/cgtd-reauth/SKILL.md
git commit -m "fix: cgtd-reauth — add Notion MCP stuck-session recovery instructions"
```

---

## Task 4: gtd-interview/SKILL.md — expand question 3 into 3a/3b/3c, update overlay logic

**Files:**
- Modify: `skills/gtd-interview/SKILL.md`

This is the most complex edit. Read the current question 3 and section 6.3 carefully before editing.

### 4a — Replace question 3 with three sub-questions

- [ ] **Find current question 3**

```bash
grep -n "отдельная база для.*проект\|Tasks.*URL\|Tasks.*нет" skills/gtd-interview/SKILL.md | head -5
```

Expected: line with «У тебя есть отдельная база для **проектов / многошаговых задач** (Tasks)?»

- [ ] **Apply the edit**

Replace the existing question 3 block:
```
3. «У тебя есть отдельная база для **проектов / многошаговых задач** (Tasks)? Если да — URL. Если нет — напиши `нет`.»
```
with:
```
3. «У тебя есть отдельная база для **Проектов** — многошаговых целей верхнего уровня (например "Построить дом", "Запустить продукт")? Если да — URL; если нет — `нет`.» Save DB ID into `config.notion.projects_id`. Set `config.gtd.has_projects_db: true` if URL provided, `false` if "нет".

4. «У тебя есть отдельная база для **Задач** — конкретных шагов внутри проектов (например "Залить фундамент", "Подключить отопление")? Если да — URL; если нет — `нет`.» Save DB ID into `config.notion.tasks_id`. Set `config.gtd.has_tasks_db: true` if URL provided, `false` if "нет". *(Все четыре комбинации валидны: оба / только Projects / только Tasks / ни того ни другого.)*

5. «Как ты ведёшь расписание рядом с Next Actions? `1)` Calendar и NA — одна система (NA сразу попадают в Календарь) `2)` раздельно — NA в Notion, встречи в Google Calendar `3)` не использую Календарь для планирования.» Save `config.gtd.calendar_integration: "unified" | "separate" | "none"`.
```

Renumber the remaining original questions (4 → 6, 5 → 7, 6 → 8, 7 → 9, 8 → 10).

- [ ] **Verify**

```bash
grep -n "has_projects_db\|has_tasks_db\|calendar_integration" skills/gtd-interview/SKILL.md
```

Expected: all three config keys present.

```bash
grep -n "^[0-9]\+\." skills/gtd-interview/SKILL.md | tail -10
```

Expected: sequence ends at 10 (previously 8).

---

### 4b — Update section 6.3 overlay logic

- [ ] **Find the section 6.3 overlay generator**

```bash
grep -n "6.3\|generate skill overlay\|If user has no Tasks" skills/gtd-interview/SKILL.md
```

- [ ] **Apply the edit**

In section 6.3, find the existing check:
```
- **process-inbox** — replace hardcoded Status values … If user has no Tasks DB, drop the «multi-step → Tasks» branch and merge into Next Actions. If user has no Notes DB, drop the Notes branch and inline references into Inbox body.
```

Replace the «If user has no Tasks DB» clause with:

```
- **process-inbox** — replace hardcoded Status values with `config.gtd.next_actions.status_values.*`. Replace data-source IDs with `config.notion.*_id`. Routing logic adapts to the user's DB structure:

  | `has_projects_db` | `has_tasks_db` | Behavior |
  |---|---|---|
  | false | false | All multi-step work → Next Actions. Drop Tasks/Projects routing branches. |
  | true | false | Multi-step goals → `config.notion.projects_id`. Steps tracked as NA directly. |
  | false | true | Steps → `config.notion.tasks_id`. No Projects level — route project-like items to Tasks. |
  | true | true | Full hierarchy: Goals → Projects, Steps → Tasks, Atomic → Next Actions. |

  If a flag is `true` but the corresponding `_id` is null (URL validation failed during interview), emit a Telegram warning on first run: «Настроена база [Projects/Tasks] но ID не найден — проверь `/gtd-config`.»

  For calendar: if `calendar_integration: "unified"`, dedup Next Actions against Calendar events by event_id before creating. If `"separate"`, create independently. If `"none"`, omit Calendar references.
```

Also in section 6.3, find the morning-ritual and evening-review overlay instructions and add:
```
- **morning-ritual** / **evening-review** — for `calendar_integration: "unified"`: present Calendar and NA as one merged schedule, deduplicate by event_id. For `"separate"`: two parallel sections (Calendar, then NA). For `"none"`: omit Calendar section.
```

- [ ] **Verify**

```bash
grep -n "has_projects_db\|has_tasks_db\|calendar_integration" skills/gtd-interview/SKILL.md | wc -l
```

Expected: ≥ 6 occurrences (questions + overlay table + overlay calendar section).

- [ ] **Commit**

```bash
git add skills/gtd-interview/SKILL.md
git commit -m "fix: gtd-interview — separate Projects/Tasks/Calendar questions, full overlay matrix"
```

---

## Task 5: init/SKILL.md — add pre-flight MCP check

**Files:**
- Modify: `skills/init/SKILL.md`

- [ ] **Find the "Hand off" section (step 5)**

```bash
grep -n "Hand off\|Bootstrap done\|✓ Bootstrap" skills/init/SKILL.md
```

Expected: step 5, around line 70.

- [ ] **Apply the edit**

Before the existing step 5 "Hand off" section, insert a new step:

```markdown
### 4.5 Pre-flight MCP check

Before printing "✓ Bootstrap done", verify that both MCPs are reachable (not just not-yet-authed):

1. Call `mcp__google-workspace__list_calendars` with any placeholder email (e.g. `test@example.com`).
   - If it returns an OAuth URL → expected, everything is wired. Do not warn.
   - If it returns a tool-layer error (connection refused, server not found, non-200 that is not a redirect) → print in terminal: «⚠ google-workspace MCP is not responding. Check `data/claude-home/settings.json` and run `docker compose restart`.»

2. Call `mcp__notion__notion-search` with an empty query `""`.
   - If it returns an OAuth URL or any valid response → expected. Do not warn.
   - If it returns a tool-layer error (network failure, unreachable server) → print: «⚠ Notion MCP is not responding. Check `data/claude-home/settings.json`.»

Auth errors (OAuth URL in the response body) are the normal pre-auth state — do not flag them. Only flag hard connection/configuration failures.

Continue to step 5 regardless (MCP issues can be fixed before the user runs `/gtd-config`).
```

- [ ] **Verify**

```bash
grep -n "Pre-flight MCP\|tool-layer error\|4\.5" skills/init/SKILL.md
```

Expected: all strings present.

- [ ] **Commit**

```bash
git add skills/init/SKILL.md
git commit -m "fix: init — add pre-flight MCP connectivity check before bootstrap complete"
```

---

## Task 6: docker-compose files — add ALLOWED_FILE_DIRS

**Files:**
- Modify: `docker-compose.yml`
- Modify: `docker-compose.example.yml`

### 6a — docker-compose.yml

- [ ] **Check current environment blocks**

```bash
grep -n "environment\|TZ=\|CGTD_DATA" docker-compose.yml
```

- [ ] **Apply the edit**

For the `assistant` service, add after `- TZ=Europe/Berlin`:
```yaml
      - ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

For the `assistant_user2` service, add after `- TZ=Europe/Berlin`:
```yaml
        - ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

- [ ] **Verify**

```bash
grep -c "ALLOWED_FILE_DIRS" docker-compose.yml
```

Expected: `2` (one per service).

---

### 6b — docker-compose.example.yml

- [ ] **Check current environment blocks**

```bash
grep -n "environment\|CGTD_DATA" docker-compose.example.yml
```

- [ ] **Apply the edit**

For the `work` service, add to its `environment` block:
```yaml
      - ALLOWED_FILE_DIRS=/root/.claude/channels/telegram/inbox:/root/.workspace-mcp/attachments
```

For the `personal` service, same addition.

- [ ] **Verify**

```bash
grep -c "ALLOWED_FILE_DIRS" docker-compose.example.yml
```

Expected: `2`.

- [ ] **Commit**

```bash
git add docker-compose.yml docker-compose.example.yml
git commit -m "fix: docker-compose — add ALLOWED_FILE_DIRS for telegram inbox → Drive upload path"
```

---

## Task 7: settings.json files — add permissions block

**Files:**
- Modify: `.claude/settings.json.example`
- Modify: `data/claude-home/settings.json`

### 7a — .claude/settings.json.example

- [ ] **Read current content**

```bash
cat .claude/settings.json.example
```

Expected: only `mcpServers` block, no `permissions`.

- [ ] **Apply the edit**

Add a `permissions` key at the top level, before `mcpServers`:

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
  "mcpServers": {
    ...existing content unchanged...
  }
}
```

- [ ] **Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('.claude/settings.json.example')); print('valid')"
```

Expected: `valid`.

---

### 7b — data/claude-home/settings.json

- [ ] **Read current permissions block**

```bash
python3 -c "import json; d=json.load(open('data/claude-home/settings.json')); print(d.get('permissions'))"
```

Expected: `{'allow': ['Bash*']}`

- [ ] **Apply the edit**

Extend `permissions.allow` array to:
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

- [ ] **Verify JSON is valid and permissions extended**

```bash
python3 -c "import json; d=json.load(open('data/claude-home/settings.json')); print(len(d['permissions']['allow']))"
```

Expected: `6`.

- [ ] **Commit**

```bash
git add .claude/settings.json.example data/claude-home/settings.json
git commit -m "fix: settings.json — add Read/Write/MCP permissions to reduce permission prompts"
```

---

## Task 8: docs/google-setup.md — Redirect URI callout + Production explanation

**Files:**
- Modify: `docs/google-setup.md`

### 8a — Redirect URI callout (step 4)

- [ ] **Find the redirect URI line**

```bash
grep -n "oauth2callback\|redirect" docs/google-setup.md
```

- [ ] **Apply the edit**

Find the line:
```
   - Authorized redirect URI: `http://localhost:8000/oauth2callback`.
```

Add immediately after it:

```markdown
   > **⚠ Critical:** The redirect URI must be exactly `http://localhost:8000/oauth2callback`. A missing or mis-typed URI is the most common cause of OAuth failures. Double-check it before clicking Create.
```

- [ ] **Verify**

```bash
grep -n "Critical\|mis-typed" docs/google-setup.md
```

Expected: 1 match.

---

### 8b — Expand Production vs Testing section

- [ ] **Find the section**

```bash
grep -n "7-day\|Testing.*status\|Publish.*Production" docs/google-setup.md
```

- [ ] **Apply the edit**

Find the current section «Avoiding the 7-day refresh-token expiry» and locate the «Publish App» sentence. After it, add the following clarification (before «After publishing»):

```markdown
**Important: «Publish to Production» does not make your app public.** It does not list the app in any Google directory, does not require Google's app verification, and does not affect who can use it. The only effect for personal use is removing the 7-day token limit.

During OAuth you will see an «unverified app» warning — this is normal. Click «Advanced → Go to *your-app-name* (unsafe)» to proceed. The warning exists for end users of public apps; for your own personal app it is safe to bypass.

You do **not** need to complete Google's app verification process. Verification is only required to suppress the warning for *other people* using a public app.
```

- [ ] **Verify**

```bash
grep -n "does not make your app public\|unverified app" docs/google-setup.md
```

Expected: both strings present.

- [ ] **Commit**

```bash
git add docs/google-setup.md
git commit -m "docs: google-setup — add redirect URI warning, clarify Production vs Testing publishing"
```

---

## Task 9: README.md — three small fixes

**Files:**
- Modify: `README.md`

### 9a — Fix `$EDITOR .env`

- [ ] **Find the line**

```bash
grep -n "EDITOR .env" README.md
```

- [ ] **Apply the edit**

Replace:
```
$EDITOR .env             # paste GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET
```
with:
```
nano .env                # or: vim .env  — paste GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET
```

- [ ] **Verify**

```bash
grep "nano .env" README.md
```

Expected: 1 match. No `$EDITOR`.

---

### 9b — Add `cd cgtd` after `git clone`

- [ ] **Find the clone line**

```bash
grep -n "git clone" README.md
```

- [ ] **Apply the edit**

Replace:
```
git clone https://github.com/gothamite/cgtd.git
cd cgtd
```

If `cd cgtd` is already there, skip this step (verify with grep first). If not, add it immediately after the clone line.

- [ ] **Verify**

```bash
grep -A1 "git clone" README.md
```

Expected: next line is `cd cgtd`.

---

### 9c — Add MCP connectivity note to step 2

- [ ] **Find the `/init-cgtd` description in step 2**

```bash
grep -n "init-cgtd\|Bootstrap" README.md
```

- [ ] **Apply the edit**

After the line describing what `/init-cgtd` does («This walks you through three things only…»), add:

```markdown
> The bootstrap includes a quick MCP connectivity check. If Google or Notion MCPs aren't reachable, you'll see a warning in the terminal — fix `data/claude-home/settings.json` and run `docker compose restart` before proceeding.
```

- [ ] **Verify**

```bash
grep -n "MCP connectivity\|docker compose restart" README.md
```

Expected: 1 match.

- [ ] **Commit**

```bash
git add README.md
git commit -m "docs: README — fix \$EDITOR, add cd cgtd, add MCP connectivity note"
```

---

## Final verification

- [ ] **Check all commits are in order**

```bash
git log --oneline -12
```

Expected: 9 commits starting from «fix: inbox-router» through «docs: README».

- [ ] **Check no regressions in skill files (all required sections still present)**

```bash
grep -l "Pre-flight\|Logging wrapper\|Failure modes" skills/*/SKILL.md | wc -l
```

Expected: 4+ skill files all retain their standard sections.

- [ ] **Push**

```bash
git push origin main
```
