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
4. «Хочешь задать боту персонаж/характер для общения? Например: строгий помощник, дружелюбный ассистент, краткий и деловой, или придумай свой. Пришли описание в свободной форме — или напиши `нет`, чтобы оставить нейтральный тон.» / «Want to give the assistant a personality? Describe it freely (e.g. "friendly", "blunt and concise", "a sarcastic hacker") or say `no` for neutral.»

   If user says «нет» / «no» / «skip» / equivalent → do nothing, no file created.
   Otherwise → save the user's description verbatim into `/data/claude-home/projects/-app/memory/user_persona.md` with this structure:
   ```markdown
   ---
   name: user-persona
   description: "Custom assistant persona defined during setup"
   metadata:
     type: user
   ---
   <user's description verbatim>

   **How to apply:** Use this tone and character in all Telegram replies. Don't let the persona override accuracy on important tasks — accuracy first, style second.
   ```
   Also append to `/data/claude-home/projects/-app/memory/MEMORY.md`:
   `- [Assistant persona](user_persona.md) — <one-line summary of the persona>`

From this point on, all assistant messages use `config.user.locale`.

## Section 2 — Drive-account-purpose explanation

Before asking about Google accounts, send one message explaining **why** we need to know which Google account is primary:

> Сейчас я попрошу авторизовать один или несколько Google-аккаунтов — я буду читать Gmail и Calendar из каждого. **Один из них** будет «основным»: на его Google Drive я создам папку, в которую буду складывать файлы, которые ты пересылаешь мне в Telegram (фото, PDF, голосовые). Каждая запись в Notion Inbox получит ссылку на сохранённый файл. Обычно основной = личный. Ок?

(English/German equivalents.) Wait for "ok" / acknowledgement.

## Section 3 — Google OAuth (multi-account loop)

Ask: «Перечисли все Gmail-адреса, которые надо опрашивать, через запятую. Первый станет основным (туда складываем вложения).»

For each `email` in the user's list:

1. Reply with «Сейчас открою для тебя ссылку авторизации `<email>`. **Открой её на компьютере, где запущен Docker** (на телефоне не сработает — редирект уходит на `localhost:8000`).»
2. Call `mcp__google-workspace__list_calendars user_google_email=<email>` — server returns an OAuth URL on first call.
3. Send the URL as a Telegram message.
4. Wait for the user to reply «готово» / «done» / equivalent.
5. Retry `list_calendars`. If success → save `<email>` into `config.google.accounts[]`, advance. If still failing → reply «не получилось — давай попробуем ещё раз» with the URL again.

After the loop: confirm the primary («Основной = `<first email>`. Менять?»). Save `config.google.primary`.

## Section 4 — Notion API key

1. Call `mcp__notion__notion-search` with `query=""`.
   - If it returns valid results or an empty list → key already configured (came from `.env`). Advance `init-progress.json` `section` to `"drive_folder"` and continue to Section 5 (Drive folder).
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

5. On next `/gtd-config` invocation: state machine loads `section = "drive_folder"` and resumes there. At the top of the `drive_folder` handler, call `mcp__notion__notion-search` with `query=""` to verify connectivity. If it fails, tell the user the key isn't working and prompt them to check `.env` / restart again. If it succeeds, proceed normally.

## Section 5 — Drive folder

Auto-create the inbox-attachments folder on the primary account's Drive:

```
mcp__google-workspace__create_drive_folder
  user_google_email = <config.google.primary>
  folder_name = "Notion Inbox Attachments"
```

Save `folder_id` into `config.google.drive_inbox_folder_id`. Reply «✓ создал папку `Notion Inbox Attachments` на Drive `<primary>` — туда будут попадать пересланные тобой файлы».

## Section 6 — GTD interview (the customization core)

This is the section where the user's existing Notion layout — or absence of one — becomes the assistant's vocabulary.

### 6.1 — does the user already have a GTD setup in Notion?

Ask: «У тебя уже настроена GTD-система в Notion (Inbox, Next Actions, проекты, заметки)? `да` / `нет`».

**If "нет":** offer to create the default layout.

> Я могу создать тебе четыре базы (Inbox, Next Actions, Tasks, Notes) и страницу-архив под одной родительской страницей. Это «дефолтная» схема репозитория — все скиллы из коробки работают с ней. Создать?

If yes:
- Ask the user for the URL of any Notion page where the GTD parent should live (or just «создать на верхнем уровне workspace»).
- Call `mcp__notion__notion-create-pages` to create:
  - Parent page «🗂 GTD»
  - Inside it: 4 databases (Inbox, Next Actions, Tasks, Notes) with the schemas from the OLD `notion-setup.md` (Inbox: Name/Source/Created/URL; Next Actions: Name/Status/Date/Project/Eisenhower; Tasks: Name/Status/Deadline; Notes: Name/Category/Tags/Source/URL)
  - One page «📦 Inbox Archive»
- Save the data_source IDs into `config.notion.{inbox,next_actions,tasks,notes,inbox_archive_page}_id`.
- Skip 6.2 — user gets the default skill behavior with no overlays needed.

**If "да":** run the interview below.

### 6.2 — interview an existing setup

Ask, one question per Telegram message, waiting for reply:

1. «Скинь URL твоей **Inbox** базы (или эквивалента — куда падает всё непомеченное).»
2. «Скинь URL **Next Actions** или эквивалента (атомарные действия с датой).»
3. «У тебя есть отдельная база для **Проектов** — многошаговых целей верхнего уровня (например "Построить дом", "Запустить продукт")? Если да — URL; если нет — `нет`.» Save DB ID into `config.notion.projects_id`. Set `config.gtd.has_projects_db: true` if URL provided, `false` if "нет".

4. «У тебя есть отдельная база для **Задач** — конкретных шагов внутри проектов (например "Залить фундамент", "Подключить отопление")? Если да — URL; если нет — `нет`.» Save DB ID into `config.notion.tasks_id`. Set `config.gtd.has_tasks_db: true` if URL provided, `false` if "нет". *(Все четыре комбинации валидны: оба / только Projects / только Tasks / ни того ни другого.)*

5. «Как ты ведёшь расписание рядом с Next Actions? `1)` Calendar и NA — одна база (NA сразу попадают в Календарь) `2)` раздельно — NA в Notion, встречи в Google Calendar `3)` не использую Календарь для планирования.» Save `config.gtd.calendar_integration: "unified" | "separate" | "none"`.

6. «База для **заметок / референсов** (статьи, контакты, идеи)? URL или `нет`.»
7. «Куда ты архивируешь обработанные Inbox-записи? URL страницы-архива, или `удаляю` / `меняю статус` / `нет`.»

For each provided URL: call `mcp__notion__retrieve-a-page` to validate access. If 403/404, reply «не вижу — поделись страницей с интеграцией (Share → Connections → выбери твою интеграцию `<config.notion.integration_name>`) и пришли URL ещё раз». Save IDs into `config.notion.*_id`.

Then probe the schemas. For each provided database, call `mcp__notion__retrieve-a-page` and inspect the property list:

8. For the Inbox/Next Actions/Tasks DBs that exist:
   - Find the **Status** property (any property of type `status` or `select`). Send: «В `<DB>` твой статус-проперти называется `<name>` со значениями: `<list>`. Какое значение означает «не сделано / новое»? «в работе»? «сделано»? «отменено»? «отложено / someday»? Можно пропустить, если значения не подходят.»
   - Save into `config.gtd.<db>.status_field` + `status_values.{open,in_progress,done,cancelled,deferred}`.
   - Find the **Date** / **Deadline** property if present. Send: «Поле даты — `<name>`? Используется для дедлайна или для расписания?» Save.
   - Find any **priority** property (Eisenhower, P1-P4, etc.). Send: «Есть приоритеты? Поле `<name>` со значениями `<list>` — это что? Эйзенхауэр / P1-P4 / другое / не используется.» Save into `config.gtd.priority_scheme`.

9. Notes DB (if present): «Какие у тебя поля в Notes — категория, тэги, источник? Перечисли.» Save into `config.gtd.notes.fields`.

10. Free-form: «Расскажи коротко своими словами, как ты пользуешься этой системой день в день. Что ты делаешь утром? Что вечером? Как обрабатываешь Inbox? Что особенного я должен учитывать?» — save the answer verbatim into `config.gtd.user_narrative`. The morning-ritual / evening-review / process-inbox skills will read this when generating their output to align with the user's voice.

### 6.3 — generate skill overlay

Based on `config.gtd.*`, write customized SKILL.md files into `/data/skills-overlay/<name>/SKILL.md` for any skill whose default behavior needs adapting:

- **process-inbox** — replace hardcoded Status values («Not started» / «Done» / «Cancelled» / «Someday/Maybe») with `config.gtd.next_actions.status_values.*`. Replace data-source IDs with `config.notion.*_id`. Routing logic adapts to the user's DB structure:

  | `has_projects_db` | `has_tasks_db` | Behavior |
  |---|---|---|
  | false | false | All multi-step work → Next Actions. Drop Tasks/Projects routing branches. |
  | true | false | Multi-step goals → `config.notion.projects_id`. Steps tracked as NA directly. |
  | false | true | Steps → `config.notion.tasks_id`. No Projects level — route project-like items to Tasks DB as the closest available container (not to Next Actions). |
  | true | true | Full hierarchy: Goals → Projects, Steps → Tasks, Atomic → Next Actions. |

  If a flag is `true` but the corresponding `_id` is null (URL validation failed during interview), emit a Telegram warning on first run: «Настроена база [Projects/Tasks] но ID не найден — проверь `/gtd-config`.»

  For calendar: if `calendar_integration: "unified"`, dedup Next Actions against Calendar events by event_id before creating. If `"separate"`, create independently. If `"none"`, omit Calendar references.

  If user has no Notes DB, drop the Notes branch and inline references into Inbox body.
- **morning-ritual** — replace status filter («Status ∉ {Done, Cancelled}») with the user's terms. Replace Eisenhower references with `config.gtd.priority_scheme` (drop entirely if `none`). For `calendar_integration: "unified"`: present Calendar and NA as one merged schedule, deduplicate by event_id. For `"separate"`: two parallel sections (Calendar, then NA). For `"none"`: omit Calendar section.
- **evening-review** — same status replacements. Same `calendar_integration` rendering as morning-ritual: for `"unified"` → merged schedule with dedup by event_id; for `"separate"` → two parallel sections; for `"none"` → omit Calendar section.
- **proactive-inbox** — replace status terms; if user has no Notes DB, route newsletters/references to Inbox body instead.
- **inbox-router** — replace `notion.inbox_id` reference (already config-driven, so usually no overlay needed unless user opted out of Inbox-everything).

Method: read each shipped `/app/skills/<name>/SKILL.md`, run substitution on the named hardcoded strings, write the result to `/data/skills-overlay/<name>/SKILL.md`. Substitutions are recorded in `config.gtd.overlay_substitutions[]` so a future `/cgtd-reset-skills` knows what was changed.

If `config.gtd.user_narrative` is non-empty, append a `## User narrative` section to each generated overlay so every skill run picks up the user's day-in-the-life context.

After writing overlays, the entrypoint's per-skill symlinking (already in `entrypoint.sh`) will pick them up on next session start. The current Telegram channel session must be restarted for skills to reload — tell the user at the end.

## Section 7 — schedule

Ask: «Расписание — когда я тебе пингую? Выбери пресет: `1)` flex (только утренний и вечерний пинг, без жёстких часов) `2)` 9-to-5 офис `3)` сменный график `4)` свой».

For each preset, fill `config.schedule.weekday_blocks` and `config.schedule.weekend_rule`. Custom = ask block by block.

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
   - Skill name mapping: `morning_ritual`→`morning-ritual`, `evening_review`→`evening-review`, `process_inbox`→`process-inbox`.
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
- User's existing setup is too divergent to map cleanly → save `config.gtd.unmappable_warning: true` and the verbatim user answer; skills run in degraded mode (skip Status filtering, surface everything) and the user is told.
