---
name: gtd-interview
description: Telegram-driven interview that finishes setup after init-cgtd's terminal bootstrap. Asks the user about their existing Notion GTD layout (or creates one if absent), runs Google + Notion OAuth, picks a Drive folder, captures schedule preferences, and writes config.json + skill overlays adapted to the user's vocabulary. Multi-turn, resumable via /data/init-progress.json.
---

# Telegram interview (Phase 2)

Triggered when the user DMs the bot `/gtd-config` (first time or to reconfigure). The whole conversation happens over Telegram. The terminal is no longer needed except for OAuth links, which the user opens on the same machine running Docker (Telegram Desktop strongly recommended).

This skill replaces what the old monolithic init skill used to do in the terminal.

## State machine

Persist progress to `/data/init-progress.json`:

```json
{
  "section": "user" | "drive_account_explanation" | "google_oauth" |
             "drive_folder" | "gtd_interview" |
             "schedule" | "jobs" | "finalize" | "done",
  "section_state": { ... per-section scratch ... },
  "started_at": "<iso>",
  "config_draft": { ... building toward /data/config.json ... }
}
```

On every inbound message, load progress, dispatch to the current section's handler. Each section advances the cursor on success. If the user disconnects mid-flow, next `/gtd-config` resumes where they left off. Reply to every step with one Telegram message; never two messages back-to-back without a user turn between.

## Pre-flight

1. Read `/data/config.json`. If `init_complete: true` → present a numbered menu (Telegram message): «1) reconfigure user 2) reconfigure Google 3) reconfigure Notion 4) reconfigure schedule 5) reconfigure jobs 6) regenerate skill overlay 7) full re-init 0) exit». Branch to the matching section. Otherwise proceed with full flow below.
2. Read `install_id` from `/data/install_id`.
3. Confirm the user's Telegram `chat_id` from the inbound `<channel>` tag and save into `config_draft.telegram.chat_id`.

## Section 1 — user

Four messages, one question each, wait for reply between:

1. «Какой язык использовать для всех ответов и сводок? `en` / `ru` / `de`. По умолчанию `en`.» / «What language should I use? en / ru / de.» — save `config.user.locale`.
2. «Как тебя называть? Имя — этого хватит.» / «What should I call you? First name is enough.» — save `config.user.name`.
3. «Часовой пояс? Я предполагаю `<auto-detect from /etc/timezone or TZ>`. Подтверди или пришли свой (формат `Europe/Berlin`).» — save `config.user.timezone`.

From this point on, all assistant messages use `config.user.locale`.

## Section 2 — Google opt-in (optional)

Ask one message:

> Хочешь подключить Google (Gmail + Calendar)?
> Это позволит мне:
> — читать Inbox и добавлять важное в Notion автоматически
> — видеть твои встречи при планировании дня
> — сохранять файлы, которые ты пересылаешь мне, на Google Drive
>
> Всё это опционально — можно работать только с Notion. Подключить? `да / нет`

(English/German equivalents.)

**If "нет" / "no" / "skip":**
- Set `config.google.enabled: false`, `config.google.drive_enabled: false`.
- Advance to Section 4 (Notion API key). Skip Section 3 and Section 5.
- Note in Telegram: «Ок. Gmail и Calendar подключить можно позже через `/gtd-config`.»

**If "да" / "yes":** proceed to Section 3.

## Section 3 — Google OAuth (multi-account loop)

Ask: «Перечисли все Gmail-адреса, которые надо опрашивать, через запятую. Первый станет основным — на него буду сохранять вложения из Telegram (если захочешь Drive).»

For each `email` in the user's list:

1. Reply: «Сейчас открою ссылку авторизации для `<email>`. **Открой на компьютере, где запущен Docker** (на телефоне не сработает — редирект уходит на `localhost:8000`).»
2. Call `mcp__google-workspace__list_calendars user_google_email=<email>` — server returns an OAuth URL on first call.
3. Send the URL as a Telegram message.
4. Wait for the user to reply «готово» / «done» / equivalent.
5. Retry `list_calendars`. If success → save `<email>` into `config.google.accounts[]`, advance. If still failing → retry with the URL again.

After the loop:
- Confirm the primary («Основной = `<first email>`. Менять?»). Save `config.google.primary`.
- Set `config.google.enabled: true`.
- Ask: «Хочешь чтобы я сохранял вложения из Telegram на Google Drive? Тогда в каждой записи Inbox будет ссылка на файл. `да / нет`»
  - If yes → set `config.google.drive_enabled: true`. Drive folder will be created in Section 5.
  - If no → set `config.google.drive_enabled: false`. Skip Section 5.

## Section 4 — Notion API key

1. Call `mcp__notion__API-post-search` with `query=""`.
   - If it returns valid results or an empty list → key already configured (came from `.env`). Advance `init-progress.json` `section` to `"drive_folder"` if `config.google.drive_enabled` is true, else to `"gtd_interview"`. Continue to the appropriate section.
   - If it returns an error (MCP not connected / key missing) → proceed to step 2.

2. Send Telegram message:
   > Нужен Notion Internal Integration Token:
   > 1. Открой notion.so → Settings → Connections → Develop or manage integrations → New integration
   > 2. Type: **Internal**. Назови как хочешь (например `cgtd` или своё имя).
   > 3. Скопируй **Internal Integration Token** (начинается с `ntn_` или `secret_`) и пришли сюда.
   > 4. Запомни, как назвал интеграцию — оно понадобится при настройке баз Notion.

3. When user sends the token:
   - Validate format: must start with `ntn_` or `secret_`. If invalid, ask again.
   - Save to `config_draft.notion.api_key` and write to `/data/config.json`.
   - Ask: «Как ты назвал интеграцию?» Save the name to `config_draft.notion.integration_name`.
   - Advance `init-progress.json` `section` to `"drive_folder"`.

4. Reply:
   > ✓ Токен сохранён. Нужен перезапуск контейнера чтобы он подхватился:
   > ```
   > docker compose restart assistant
   > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
   > ```
   > После перезапуска напиши `/gtd-config` — продолжим с настройки баз данных Notion.

5. On next `/gtd-config` invocation: state machine loads `section = "drive_folder"` and resumes there. At the top of the `drive_folder` handler, call `mcp__notion__API-post-search` with `query=""` to verify connectivity. If it fails, tell the user the key isn't working and prompt them to check `.env` / restart again. If it succeeds, proceed normally.

## Section 5 — Drive folder (only if `config.google.drive_enabled: true`)

Skip this section entirely if `config.google.drive_enabled` is false.

Auto-create the inbox-attachments folder on the primary account's Drive:

```
mcp__google-workspace__create_drive_folder
  user_google_email = <config.google.primary>
  folder_name = <config.google.drive_inbox_folder_name or "Notion Inbox Attachments">
```

Save `folder_id` into `config.google.drive_inbox_folder_id`. Reply «✓ создал папку на Drive `<primary>` — туда будут попадать вложения из Telegram».

## Section 6 — GTD interview (the customization core)

This is where the user's existing Notion layout — whatever it looks like — becomes the assistant's vocabulary. The system has **no requirements** about DB names, hierarchy, or property names. It maps to four semantic roles and works with whatever the user has.

### Semantic roles

| Role | Purpose | Required? |
|------|---------|-----------|
| **INBOX** | Where new items land first — the entry point | Yes (at least one) |
| **ACTIONS** | Schedulable atomic tasks the user will do | Optional |
| **PROJECTS** | Multi-step goals with sub-tasks | Optional |
| **REFERENCE** | Notes, articles, contacts — info without an action | Optional |

Any role can map to the same DB as another. Multiple DBs can serve the same role. A user with only one list → INBOX = ACTIONS = that list. A user with no task list → INBOX only.

### 6.1 — discover existing Notion setup (proactive)

**Do not ask anything yet.** First, probe Notion silently:

Run all searches in parallel:
```
mcp__notion__API-post-search query=""
mcp__notion__API-post-search query="inbox"
mcp__notion__API-post-search query="tasks"
mcp__notion__API-post-search query="actions"
mcp__notion__API-post-search query="projects"
mcp__notion__API-post-search query="notes"
mcp__notion__API-post-search query="reference"
mcp__notion__API-post-search query="входящие"
mcp__notion__API-post-search query="задачи"
mcp__notion__API-post-search query="проекты"
mcp__notion__API-post-search query="заметки"
```

Collect all results where `object = "database"`. Deduplicate by `id`. Save as `section_state.discovered_dbs[]` (id, name, url). This list is reused throughout 6.2 — Steps 1–4 accept a number from this list instead of a URL paste.

**If 1+ databases found** → send ONE message:

> Нашёл в Notion следующие базы данных, к которым у меня есть доступ:
> 1. «Inbox» — notion.so/…
> 2. «Tasks» — notion.so/…
> 3. «Projects» — notion.so/…
> …
>
> Используешь какую-то из них как Inbox (для задач, проектов, заметок)? Или эти базы для другого — и лучше создать новые?

Reply options:
- **«да, вот эти» / номера** → proceed to 6.2 role assignment using the selected databases.
- **«нет, эти для другого»** → offer creation options (see below).
- **«частично»** → proceed to 6.2; user picks numbers for existing DBs and says «нет» for roles without a match.

**If 0 databases found** (integration not shared with any DB yet) → send:

> Не нашёл баз данных Notion, к которым у меня есть доступ. Создать структуру с нуля?
> `1)` Полная GTD-структура (4 базы)
> `2)` Простой список (одна база — всё в одном месте)
> `3)` Сам скажу что создавать

**Creation options (options 1/2/3):**

For **option 1** (full GTD):
- Ask for a parent page URL (or «создать на верхнем уровне»).
- Create parent page «🗂 GTD», inside it:
  - **Inbox** — Name (title), Source (text), URL (url)
  - **Actions** — Name (title), Status (status: Not started / Done / Cancelled / Someday·Maybe), Date (date), Priority (select: high / normal / low)
  - **Projects** — Name (title), Status (status: Inbox / In Progress / Done / On hold), Due (date), Priority (select: high / normal / low), Actions (relation → Actions)
  - **Notes** — Name (title), Category (select), Tags (multi-select), Source (text), URL (url)
- Save into config: `notion.capture.db_id` = Inbox ID; `notion.actions.db_id` = Actions ID; `notion.projects.db_id` = Projects ID with `actions_relation = "Actions"`; `notion.reference.db_id` = Notes ID.
- Populate all `fields.*` from the created schemas.
- Skip 6.2.

For **option 2** (single list):
- Ask for a parent page URL (or «создать на верхнем уровне»).
- Create one DB: **My List** — Name (title), Status (select: New / In Progress / Done), Date (date), Notes (text).
- Set `notion.capture.db_id` = that DB. Set `notion.actions = {same_as_capture: true}`. Leave `notion.projects` and `notion.reference` empty.
- Skip 6.2.

For **option 3**: run the interview in 6.2 (user will provide URLs or create selectively).

### 6.2 — role-based interview

`section_state.discovered_dbs[]` is already populated from 6.1. In each step, the user can reply with a **number from that list** instead of pasting a URL. One question per Telegram message. Validate every URL immediately — if 403/404, prompt: «не вижу эту базу — поделись страницей с интеграцией `<config.notion.integration_name>` (Share → Connections) и пришли снова».

---

**Step 1 — INBOX role**

If `discovered_dbs` is non-empty:
> Куда в Notion попадает всё новое — мысли, задачи, ссылки? Назови номер из списка или пришли URL.

If `discovered_dbs` is empty:
> Куда в Notion попадает всё новое — мысли, задачи, ссылки, что угодно — когда ты хочешь это не забыть? Скинь URL базы данных.

- If user replies with a number → resolve to `discovered_dbs[n]`. Use its id and URL directly.
- If user replies with a URL → validate access via `mcp__notion__API-retrieve-a-page`. If 403/404 → prompt to share with integration.
- If user has multiple capture points: ask for additional (by number or URL); store all as array in `notion.capture`.
- Save to `notion.capture.db_id`, `notion.capture.db_name`.

**Probe Inbox schema** — run silently, no questions yet:
1. Call `mcp__notion__API-retrieve-a-page` on the DB to get all properties.
2. Auto-map fields using these heuristics:
   - Title-type property → `capture.fields.title`
   - Status/select field → `capture.fields.status`. Auto-map values by name:
     - Contains "done", "готово", "complete", "finished", "closed" → `status_done`
     - Contains "cancel", "отменен", "won't", "не буду" → `status_cancelled`
     - Contains "someday", "maybe", "когда-нибудь", "отложен", "later", "потом" → `status_deferred`
     - Contains "progress", "в работе", "doing", "active", "в процессе" → `status_in_progress`
     - Remaining open/first value → `status_open`
   - Date-type property → `capture.fields.date`
   - Select/number property with values like "high/medium/low", "P1/P2/P3", "Q1/Q2/Q3/Q4", "urgent/important" → `capture.fields.priority`
   - All other properties → `capture.fields.extra[]`
3. Send ONE confirmation message only if mapping is ambiguous:
   > Нашёл в `<DB name>`: статус = `<field>` (`open`→«<val>», `done`→«<val>», `deferred`→«<val>»), дата = `<field or нет>`, приоритет = `<field or нет>`. Всё верно?
   
   If mapping is unambiguous (values clearly named) → skip the question entirely, proceed silently.
4. If no status field found → `capture.fields.status = null`. No question needed.

This full probe result is reused when ACTIONS or PROJECTS role is `same_as_capture`.

---

**Step 2 — ACTIONS role**

> Где находятся конкретные действия или задачи, которые нужно выполнить? Это та же база или отдельная? (номер из списка / URL / «та же»)

Reply options:
- **«та же»** / «одна база» / номер совпадает с INBOX → set `notion.actions.same_as_capture = true`. Copy fields from Inbox probe into `notion.actions.fields`. No probe needed.
- **«нет»** / «не веду» / «нет такого» → `notion.actions.same_as_capture = true` silently (skills fall back to Inbox).
- **Номер из discovered_dbs** (≠ INBOX) → resolve to that DB. Validate, fetch, save to `notion.actions.db_id`, `notion.actions.db_name`. Run probe below.
- **URL** → validate, fetch, save to `notion.actions.db_id`, `notion.actions.db_name`. Run probe below.

**Probe ACTIONS schema** (if separate DB — same silent auto-mapping as Inbox):
1. Call `mcp__notion__API-retrieve-a-page` to get all properties.
2. Auto-map: status field + values, date field, priority field — same heuristics as above → save to `notion.actions.fields.*`
3. Relation fields: look for properties of type `relation`. For each found, check which DB it points to. If it points to a DB that matches the later-declared projects DB → `notion.actions.fields.project_relation = <field name>`. (If projects DB not known yet → revisit this field after Step 3.)
4. Send one confirmation only if ambiguous. Skip if clear.

---

**Step 3 — PROJECTS role**

> Есть ли место для многошаговых целей или проектов? Отдельная база, та же что и действия, та же что и первая, или нет? (номер из списка / URL / «та же» / «нет»)

Reply options:
- **«та же что и действия»** → `notion.projects.same_as_actions = true`. Run filter detection below on the actions DB.
- **«та же что и первая»** → `notion.projects.db_id = notion.capture.db_id`. Run filter detection below on the capture DB.
- **Номер из discovered_dbs** (≠ уже назначенных) → resolve to that DB. Validate, fetch, save to `notion.projects.db_id`, `notion.projects.db_name`. Run probe below.
- **URL** → validate, fetch, save to `notion.projects.db_id`, `notion.projects.db_name`. Run probe below.
- **«нет»** → leave empty.

**Filter detection** (when projects share a DB with actions/capture):
1. Call `mcp__notion__API-retrieve-a-page` on the shared DB.
2. Look for select/multi-select fields with values that distinguish type: "Project", "Task", "Action", "Проект", "Задача", "Тип", "Type", "Kind".
3. Fetch 10–20 sample entries via `mcp__notion__API-query-data-source` to see actual field values in use.
4. If a candidate filter is found → present it:
   > Похоже, проекты от действий отличаются полем `<field>` = «<value>». Использовать это как фильтр?
5. If no field found → set `filter_property = null`. Skills treat all items uniformly.

**Probe PROJECTS schema** (if separate DB):
1. Auto-map: status (with semantic mapping), due date, priority — same heuristics.
2. Relation fields: look for relation pointing to actions DB → `notion.projects.fields.actions_relation`.
3. Send one confirmation only if ambiguous.
4. If actions_relation is found → go back and fill `notion.actions.fields.project_relation` if it was empty.

---

**Step 4 — REFERENCE role**

> Есть ли место для заметок, статей, идей — информации без конкретного действия? (номер из списка / URL / «нет»)

- **Номер из discovered_dbs** (≠ уже назначенных) → resolve to that DB. Call `mcp__notion__API-retrieve-a-page` → auto-detect: title, category/select, tags/multi-select, text fields named "source"/"url". Save to `notion.reference.fields.*`. No questions unless schema is unclear.
- **URL** → validate, call `mcp__notion__API-retrieve-a-page` → auto-detect fields. Save to `notion.reference.fields.*`. No questions unless schema is unclear.
- **«нет»** → leave empty.

---

**Step 5 — Calendar**

Do not ask which Calendar the user uses — discover it first:

**If `config.google.enabled: true`:**
1. Call `mcp__google-workspace__list_calendars` for each account in `config.google.accounts`.
2. Collect all available calendars across accounts.
3. Send ONE message:
   > Нашёл у тебя эти календари в Google: `<list with names>`. Какие использовать для планирования? (все / выбери номера / исключи ненужные)
   
   Default "все" if user doesn't specify. Save selected to `notion.calendar.google_calendars`.
4. Set `config.gtd.calendar_source: "google"` (or `"both"` if Notion Calendar is also found).

**Regardless of Google:** ask once:
> Есть ли у тебя база в Notion специально для событий/встреч (Notion Calendar)? URL или «нет».

- **URL** → validate, `mcp__notion__API-retrieve-a-page` → auto-detect date fields (look for date-type properties; first date → `date_start`, second date → `date_end`), title, status. Save to `notion.calendar.*`. Set `calendar_source` to `"notion"` or `"both"`.
- **«нет»** → skip. If Google already found → `calendar_source: "google"`.

**If Google disabled AND no Notion Calendar URL:**
- Set `calendar_source: "none"`. Say: «Без календаря система составит план-список без привязки ко времени. Подключить можно позже через `/gtd-config`.»

**If both sources found:** ask:
> Google Calendar и Notion Calendar — какой главный для рабочих задач? (google / notion)
Save to `config.gtd.calendar_integration: "google_primary" | "notion_primary"`.

**Final question** (if any calendar configured):
> NA из Notion попадают в Calendar автоматически (`unified`) или ты ведёшь их отдельно (`separate`)?
Save `config.gtd.calendar_integration: "unified" | "separate"`.

---

**Step 6 — Contexts**

Do not ask — detect first:

1. Call `mcp__notion__API-retrieve-a-page` on the actions DB (or capture DB if same).
2. Look for multi-select or select properties named "Context", "Контекст", "Tags", "Тэги", "Labels", "Category".
3. Fetch 15–20 sample entries via `mcp__notion__API-query-data-source` and scan values for @-prefixed patterns or location/tool keywords (computer, phone, home, office, shop, errands, звонок, магазин, дома).
4. **If an explicit context field is detected:**
   > Нашёл поле `<field>` с контекстами: `<list of values>`. Использовать для группировки задач при планировании?
   - User confirms → `contexts.mode: "explicit"`, `contexts.field: <field>`, `contexts.values: <detected list>`.
   - User says "no" → `contexts.mode: "auto"`.
5. **If no explicit field found but @ patterns in titles:**
   > Вижу, что в названиях задач встречаются метки типа `@computer`, `@phone`. Хочешь использовать их для группировки? Или добавить отдельное поле?
   - "использовать как есть" → `contexts.mode: "explicit"`, `contexts.field: "title"`, extract values from sample entries.
   - "добавить поле" → note in config; explain they can add manually; `contexts.mode: "auto"` for now.
   - "нет" → `contexts.mode: "auto"`.
6. **If nothing detected:**
   - Set `contexts.mode: "auto"` silently. No question asked. AI will infer context from task text at runtime.

**Step 7 — Free-form**

> Расскажи коротко своими словами как ты пользуешься этой системой день в день. Что делаешь утром? Вечером? Как обрабатываешь Inbox? Что важно учитывать?

Save verbatim to `config.gtd.user_narrative`.

---

After steps 1–7, send a confirmation summary:

> Вот как я тебя понял:
> — Inbox: `<capture.db_name>`
> — Действия: `<actions.db_name or «та же база» or «нет — всё в Inbox»>`
> — Проекты: `<projects.db_name or «нет»>`
> — Заметки: `<reference.db_name or «нет — в теле записей»>`
> — Календарь: `<calendar_source: Google / Notion "<db_name>" / оба / нет>`
> — Контексты: `<"auto — выявляю сам" or список значений>`
>
> Всё верно? Или поправить?

On confirmation → proceed to 6.3. On correction → re-ask the relevant step.

### 6.3 — generate skill overlays

Write customized SKILL.md files to `/data/skills-overlay/<name>/SKILL.md`. Method: read `/app/skills/<name>/SKILL.md`, apply substitutions, write result. Record substitutions in `config.gtd.overlay_substitutions[]`.

**Routing resolution** (computed once, used by all overlays):

```
capture_id   = config.notion.capture.db_id
capture_name = config.notion.capture.db_name

actions_id   = notion.actions.db_id if not same_as_capture else capture_id
actions_name = notion.actions.db_name if set else capture_name

projects_id   = notion.projects.db_id if not same_as_* else resolved parent id
projects_name = notion.projects.db_name if set else actions_name
projects_filter = {property: notion.projects.filter_property, value: notion.projects.filter_value} or null

reference_id   = notion.reference.db_id or null
reference_name = notion.reference.db_name or null

calendar_source      = config.gtd.calendar_source
calendar_integration = config.gtd.calendar_integration
notion_calendar_id   = notion.calendar.notion_db_id or null
google_calendars     = notion.calendar.google_calendars or []

contexts_mode   = config.gtd.contexts.mode
contexts_values = config.gtd.contexts.values
contexts_field  = config.gtd.contexts.field or null
```

**per-skill overlay rules:**

- **inbox-router** — replace capture target with `capture_id`. No other changes needed.

- **process-inbox** — substitute all DB IDs and field names from roles. Routing logic:
  - atomic action → `actions_id` (if set) else `capture_id`
  - multi-step / goal → `projects_id` (if set) else `actions_id` (if set) else `capture_id`; apply `projects_filter` if set
  - reference / info → `reference_id` (if set) else inline into Inbox entry body with 📚 prefix
  - If `actions_id == capture_id` and `projects_id == capture_id`: everything stays in one DB; use tags / status values to distinguish; do not create separate entries.
  - Replace Status values with role-specific values from config fields.

- **morning-ritual** — substitute `actions_id` as the source for today's plan. If `actions_id == capture_id`, query Inbox with date filter. Replace status values from `notion.actions.fields`. Replace priority field (omit section if null). Substitute calendar resolution: `calendar_source` drives step 2 (Google events / Notion calendar / both / none); `calendar_integration` drives dedup logic. Substitute contexts: `contexts_mode` + `contexts_values` + `contexts_field` drive step 5 grouping and step 4 slotting.

- **evening-review** — same substitutions as morning-ritual. TODAY REVIEW queries `actions_id`; if same as capture, filter by date. Calendar source for tomorrow's preview uses the same `calendar_source` resolution.

- **proactive-inbox** — route actionable items to `actions_id` (or `capture_id` if absent); reference to `reference_id` (or inline). Replace field names and status values. If `config.google.enabled: false` → overlay marks skill as no-op.

- **tasks-processing** — substitute `projects_id` as the task source. Apply `projects_filter` to all queries. Replace all status values from `notion.projects.fields.*`. Replace relation field names: `projects.fields.actions_relation` for the Projects→Actions link. If `projects_id` is empty → overlay replaces the entire skill body with a silent exit. If `projects.fields.actions_relation` is null → skip graduation logic (Part B Step 1); surface projects as-is.

If `config.gtd.user_narrative` non-empty → append a `## User narrative` section to every overlay.

After writing overlays, tell the user:
> Настройки сохранены. Перезапусти channel-сессию чтобы скиллы подхватили твою конфигурацию:
> ```
> docker compose restart assistant
> docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
> ```

## Section 7 — schedule

Ask four questions, one per message:

**7.1** «Расписание — когда я тебе пингую? Выбери пресет: `1)` flex (только утренний и вечерний пинг, без жёстких часов) `2)` 9-to-5 офис `3)` сменный график `4)` свой».

For each preset, fill `config.schedule.weekday_blocks` and `config.schedule.weekend_rule` (`flex` default). Custom = ask block by block.

**7.2** «Как предпочитаешь выходные? Например: "суббота — отдых, воскресенье — дела", "гибко, без разницы", "оба дня рабочие" — напиши своими словами. Или `пропустить`.»

Save verbatim to `config.user.weekend_preference`. Also extract a machine-readable value for `config.schedule.weekend_rule`:
- Mentions rest/leisure/chill on both days → `"rest"`
- Explicit "subbota=otdykh, voskresenye=dela" or similar asymmetric split → `"custom"` (save the split in `config.user.weekend_preference`)
- No preference / flexible / both same → `"flex"`

**7.3** Lunch time — **discover before asking:**

If `config.google.enabled: true`: call `mcp__google-workspace__get_events` for the next 14 days across all configured calendars. Look for recurring events with titles containing "lunch", "обед", "Mittagessen", "lunch break", "обеденный перерыв". Extract the most common start time. If found, pre-fill `lunch_home` / `lunch_work` based on whether the event is on a weekday and which calendar it's in. Skip the question if both values are confidently determined.

If values not found via Calendar (or Google disabled) → ask:
> «В какое время обычно обедаешь? Напиши: дома (выходные, удалёнка) и на работе. Например: "дома — 14:30, работа — 12:30". Или `пропустить`.»

Parse and save to `config.user.lunch_home` (e.g. `"14:30"`) and `config.user.lunch_work` (e.g. `"12:30"`). If skipped, leave empty (skills will use a reasonable midday default).

**7.4 — AI persona (опционально)**

Send message:
> Последний шаг — хочешь придумать мне характер? Могу быть кем угодно: деловой ассистент, дружелюбный напарник, саркастичный персонаж из фантастики — или любой твой вариант. Дай имя и описание, или напиши «нет».

If user says нет/no/skip → set `config.user.persona_file = null`. Done, move to Section 8.

Otherwise:
1. From user's reply extract: **name** (for file slug, e.g. "jules"), **description** (tone, traits, voice, any references). If description is thin, ask one follow-up: «Что-то ещё — тон, стиль, что-то что нельзя нарушать?» — only one follow-up, don't over-interview.

2. Slugify the name: lowercase, spaces → underscore, strip special chars (e.g. "Jules" → "jules", "Мой Ассистент" → "moy_assistent").

3. Write `/data/claude-home/projects/-app/memory/user_persona_<slug>.md`:

```markdown
---
name: user-persona-<slug>
description: "User's requested assistant persona — <Name>"
metadata:
  type: user
---

<Verbatim or lightly structured description from user.>

**Tone & character:** <key traits extracted from description>

**How to apply:** Use this tone in all Telegram replies. Keep it consistent but don't let character get in the way of accuracy or clarity on important GTD tasks.
```

4. Append to `/data/claude-home/projects/-app/memory/MEMORY.md`:
   ```
   - [Persona: <Name>](user_persona_<slug>.md) — <one-line summary of character>
   ```

5. Set `config_draft.user.persona_file = "user_persona_<slug>.md"` (saved atomically in Section 9 config write).

6. Update `/data/claude-home/CLAUDE.md` — find the line starting with `1. Read /data/config.json` and ensure it reads:
   ```
   1. Read `/data/config.json`. If `config.user.persona_file` is non-empty, also read `/root/.claude/projects/-app/memory/<config.user.persona_file>` and apply the described persona to all Telegram replies from this point on.
   ```
   If the line already contains `persona_file` → skip. If it's the old generic "Read config.json" line → replace it.

Send confirmation:
> Запомнила. Буду <Name> — <one-line summary>. Меняется с этого момента.

## Section 8 — jobs

For each of the four jobs, send a separate Telegram message:

> `proactive-inbox` — сканит Gmail+Calendar, кладёт в Notion. Включить? Расписание (будни) `13 8-20/2 * * 1-5`, (выходные) `13 8,21 * * 0,6` — подходит?

User answers yes/no + optional cron overrides (weekday and weekend separately) per job. **Do not** offer an "all enabled" Enter-default — every job is an explicit answer.

Save into `config.jobs.<name>.{enabled,cron}`. For `proactive_inbox`: save `cron_weekday` and `cron_weekend` instead of a single `cron`.

## Section 9 — finalize

1. Write `/data/config.json` atomically: merge `config_draft` with `init_complete: true`, `init_completed_at: <iso>`. Use `tmp` then `mv`.
2. Delete `/data/init-progress.json`.
3. For each enabled job, call `CronCreate`. Save resulting IDs into `config.jobs.cron_ids`:
   - For all jobs except `proactive_inbox`: one `CronCreate` with `cron` = `config.jobs.<job>.cron`, `prompt` = `Invoke skill <skill-name>. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.` Save ID to `config.jobs.cron_ids.<job_name>`.
   - For `proactive_inbox`: two `CronCreate` calls — one with `cron_weekday` expression (ID → `config.jobs.cron_ids.proactive_inbox_weekday`) and one with `cron_weekend` expression (ID → `config.jobs.cron_ids.proactive_inbox_weekend`). Both use `prompt` = `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
   - Skill name mapping: `morning_ritual`→`morning-ritual`, `evening_review`→`evening-review`, `process_inbox`→`process-inbox`, `tasks_processing`→`tasks-processing`.
   - After all CronCreate calls, write the full `config.jobs.cron_ids` block to `/data/config.json`.
4. Run a **dry-run** of each enabled skill (skill respects a `--dry-run` flag and prints what it would do). Report results.
5. Send final Telegram message:

> ✓ Готово. Я живой.
>
> Что дальше:
> - Кидай мне в чат любые мысли, фото, файлы — они падают в Notion Inbox.
> - Утренний бриф в `<morning_ritual.cron>`, вечерний обзор в `<evening_review.cron>`.
> - Команды: `/morning`, `/evening`, `/inbox`, `/status`, `/gtd-config` (этот разговор), `/cgtd-reauth google <email>` или `/cgtd-reauth notion`.
>
> Чтобы скиллы перезагрузились с твоей кастомизацией, перезапусти channel session:
> ```
> docker compose restart assistant
> docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
> ```

## Failure modes

- User abandons mid-flow → progress is on disk, `/gtd-config` resumes.
- OAuth link unreachable (port-forward issue on VPS) → reply with the SSH local-forward command from `docs/deploy-digitalocean.md`.
- Notion fetch returns 404 → tell user to share the page with the integration; pause until retry.
- Schema probing finds no recognizable Status field → reply «не нашёл status — какое поле используешь?», fall back to user-provided answer.
- User's existing setup is too divergent to map cleanly → save `config.gtd.unmappable_warning: true` and the verbatim user answer. Tell the user:

  > Не смог полностью разобрать схему твоих баз. Запущу в адаптивном режиме: буду показывать все элементы без фильтрации по статусу, а ты подскажешь что нужно исправить. Настройку можно уточнить позже через `/gtd-config`.

  **Degraded mode definition** (what each skill does when `unmappable_warning: true`):
  - **process-inbox**: creates entries with Name + body only; skips Status/Date assignment; labels output ⚠️.
  - **morning-ritual / evening-review**: fetches all NA items without Status filter; surfaces everything; labels section ⚠️.
  - **proactive-inbox**: creates entries with Name + body only; skips Status/Date.
  - **tasks-processing**: surfaces all Tasks DB items; skips Status routing; labels output ⚠️.

  After a few days, propose to revisit: «Хочешь уточнить настройку баз данных? `/gtd-config` → "reconfigure Notion".»
