---
name: inbox-router
description: Route inbound Telegram messages. While init is in progress, dispatch everything to gtd-interview. After init is complete, default behavior is "drop into Notion Inbox unless message matches a known command."
---

# Telegram message router

Triggered when a Telegram message arrives via the channel plugin (`<channel source="telegram" chat_id="..." ...>` tag in the session).

## Cron pre-flight (every message)

Before any routing, silently check and restore missing cron jobs:

1. Read `/data/config.json`. If `config.jobs.cron_ids` is absent, empty, or all values are null → skip (init not complete yet).
2. Call `CronList` → collect the set of active cron IDs.
3. For each key in `config.jobs.cron_ids`:
   - If the corresponding job has `enabled: false` in `config.jobs` (check `config.jobs.proactive_inbox.enabled` for both proactive_inbox keys; check `config.jobs.<key>.enabled` for others) → skip that key entirely.
   - If the stored ID is null or not in the active CronList set → recreate it:
     - **`proactive_inbox_weekday`**: expression = `config.jobs.proactive_inbox.cron_weekday` (fall back to `config.jobs.proactive_inbox.cron`); prompt = `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`proactive_inbox_weekend`**: expression = `config.jobs.proactive_inbox.cron_weekend` (fall back to `config.jobs.proactive_inbox.cron`); prompt = `Invoke skill proactive-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`morning_ritual`**: expression = `config.jobs.morning_ritual.cron`; prompt = `Invoke skill morning-ritual. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`evening_review`**: expression = `config.jobs.evening_review.cron`; prompt = `Invoke skill evening-review. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - **`process_inbox`**: expression = `config.jobs.process_inbox.cron`; prompt = `Invoke skill process-inbox. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
     - Save the new ID back to `config.jobs.cron_ids[key]`.
4. If any ID was recreated, write the updated `config.json` to disk.
5. No user notification. Continue to routing.

## Pre-init guard (CRITICAL)

Read `/data/config.json`. **If the file is missing OR `init_complete` is `false` OR not set:**

- If the message is `/gtd-config` or `/cgtd` (case-insensitive) → invoke `gtd-interview` skill.
- For **any other message** during pre-init: reply «Ещё не настроен. Напиши `/gtd-config` чтобы начать настройку.» / «Not configured yet. Send `/gtd-config` to start setup.» (locale guess: from message language, default English.) Do NOT route to Notion — there's no Inbox DB ID yet.
- Exit.

Only proceed past this guard if `init_complete: true`.

## Recognized commands (post-init)

Match the start of the message text:

- `/gtd-config` or `/cgtd` → invoke `gtd-interview` (reconfigure menu)
- `/cgtd-reauth google <email>` or `/cgtd-reauth notion` → invoke `cgtd-reauth` skill
- `/morning` / `/утро` → invoke `morning-ritual` immediately
- `/evening` / `/вечер` → invoke `evening-review` immediately
- `/inbox` / `/разбери` → invoke `process-inbox` immediately
- `/status` → reply with last-ok timestamps from `cron-log.sh last-ok` for each configured job
- `/cgtd-timezone <tz>` → invoke `cgtd-timezone` skill

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
> `/cgtd-timezone <tz>` — изменить часовой пояс
>
> Обычное сообщение (без `/`) → попадает в Notion Inbox.

Do NOT route unknown commands to Inbox.

## Routing logic (post-init, non-command messages)

1. Read `/data/config.json` for `notion.inbox_id`, `telegram.chat_id`, `user.locale`, `google.{primary,drive_inbox_folder_id}`.
2. Verify the message came from `config.telegram.chat_id` (channel plugin's allowlist already filters; this is belt-and-suspenders).
3. **Attachments**: if the message has an `image_path` or `attachment_file_id`:
   - **For `image_path`**: the file path is given directly in the channel tag attribute.
     1. Run `mkdir -p /root/.workspace-mcp/attachments` via Bash.
     2. Copy the file: `cp <image_path> /root/.workspace-mcp/attachments/<basename>` via Bash (extract basename from the path).
     3. Upload via `mcp__google-workspace__create_drive_file user_google_email=<config.google.primary> folder_id=<config.google.drive_inbox_folder_id> fileUrl=file:///root/.workspace-mcp/attachments/<basename>`.
     4. Delete the copy: `rm /root/.workspace-mcp/attachments/<basename>` via Bash.
   - **For `attachment_file_id`**: call `mcp__plugin_telegram_telegram__download_attachment` to get the local path, then:
     1. Run `mkdir -p /root/.workspace-mcp/attachments` via Bash.
     2. Copy: `cp <downloaded_path> /root/.workspace-mcp/attachments/<basename>` via Bash.
     3. Upload via `mcp__google-workspace__create_drive_file user_google_email=<config.google.primary> folder_id=<config.google.drive_inbox_folder_id> fileUrl=file:///root/.workspace-mcp/attachments/<basename>`.
     4. Delete the copy: `rm /root/.workspace-mcp/attachments/<basename>` via Bash.
   - Get the shareable link via `mcp__google-workspace__get_drive_shareable_link` after upload.
   - Do NOT add a Drive-upload-failed fallback here — the existing `## Failure modes` section already handles it.
4. **Apply rule files** from `/data/memory/`:
   - `feedback_implicit_dates.md` — parse «до конца зимы», "by next Friday", etc.
   - `feedback_contextual_deadlines.md` — infer deadlines from context.
   - `feedback_default_inbox.md` — when in doubt, drop without asking.
5. Create a Notion row in `config.notion.inbox_id` via `mcp__notion__notion-create-pages`. Title = first 80 chars; body = full text + Drive link if any.
6. React with `👍` via `mcp__plugin_telegram_telegram__react`. No reply text.

## Replies to pending reviews

If the message looks like a reply to an entry in `/data/pending-reviews.jsonl` (e.g. "1 done, 2 перенести"), match against the most recent unresolved entry, apply via `mcp__notion__notion-update-page`, update the file. See `morning-ritual` and `evening-review` SKILL.md for protocol.

## Failure modes

- Notion auth expired → react with `⚠️`, reply «Notion auth истёк. Запусти `/cgtd-reauth notion`». Do NOT silently drop.
- Drive upload failed → still create Inbox entry without attachment link, mention in body «(вложение не удалось загрузить)».
- Config exists but `notion.inbox_id` empty (incomplete init) → fall back to pre-init guard behavior.
