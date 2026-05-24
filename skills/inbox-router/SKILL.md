---
name: inbox-router
description: Route inbound Telegram messages. While init is in progress, dispatch everything to gtd-interview. After init is complete, default behavior is "drop into Notion Inbox unless message matches a known command."
---

# Telegram message router

Triggered when a Telegram message arrives via the channel plugin (`<channel source="telegram" chat_id="..." ...>` tag in the session).

## Pre-init guard (CRITICAL)

Read `/data/config.json`. **If the file is missing OR `init_complete` is `false` OR not set:**

- If the message is `/gtd-config` (case-insensitive) → invoke `gtd-interview` skill.
- For **any other message** during pre-init: reply «Ещё не настроен. Напиши `/gtd-config` чтобы начать настройку.» / «Not configured yet. Send `/gtd-config` to start setup.» (locale guess: from message language, default English.) Do NOT route to Notion — there's no Inbox DB ID yet.
- Exit.

Only proceed past this guard if `init_complete: true`.

## Recognized commands (post-init)

Match the start of the message text:

- `/gtd-config` → invoke `gtd-interview` (reconfigure menu)
- `/cgtd-reauth google <email>` or `/cgtd-reauth notion` → invoke `cgtd-reauth` skill
- `/morning` / `/утро` → invoke `morning-ritual` immediately
- `/evening` / `/вечер` → invoke `evening-review` immediately
- `/inbox` / `/разбери` → invoke `process-inbox` immediately
- `/tasks-processing` → invoke `tasks-processing` skill immediately
- `/cgtd-timezone <tz>` → invoke `cgtd-timezone` skill
- `/status` → reply with last-ok timestamps from `cron-log.sh last-ok` for each configured job

If the message doesn't start with `/`, route to Inbox per the logic below.

## Routing logic (post-init, non-command messages)

1. Read `/data/config.json`. Resolve capture target: `config.notion.capture.db_id` (where items land). Also read `telegram.chat_id`, `user.locale`, `google.{primary,drive_inbox_folder_id}`.
2. Verify the message came from `config.telegram.chat_id` (channel plugin's allowlist already filters; this is belt-and-suspenders).
3. **Attachments**: if the message has an `image_path` or `attachment_file_id`:
   - Download via `mcp__plugin_telegram_telegram__download_attachment`.
   - **[Drive enabled]** If `config.google.drive_enabled` is true AND `config.google.drive_inbox_folder_id` is set: upload to Drive via `mcp__google-workspace__create_drive_file user_google_email=<config.google.primary> folder_id=<config.google.drive_inbox_folder_id>`. Get the shareable link and include it in the entry body.
   - **[Drive not enabled]** Create the capture entry with the attachment filename and any accompanying text. Then **reply via Telegram** (do NOT just react): inform the user that the file was added to Notion as a text note but the actual file was not saved — to enable file storage, connect Google Drive via `/gtd-config`. The reply must happen immediately after the 📥 react; do not silently drop.
4. **Apply rule files** from `/data/memory/`:
   - `feedback_implicit_dates.md` — parse «до конца зимы», "by next Friday", etc.
   - `feedback_contextual_deadlines.md` — infer deadlines from context.
   - `feedback_default_inbox.md` — when in doubt, drop without asking.
5. Create a Notion row in `config.notion.capture.db_id` via `mcp__notion__API-post-page`. Title = first 80 chars; body = full text + Drive link if any + attachment filename. Use `config.notion.capture.fields.title` as the title property name (fallback `"Name"`).
6. React with `📥` via `mcp__plugin_telegram_telegram__react`.

## Replies to pending reviews

If the message looks like a reply to an entry in `/data/pending-reviews.jsonl` (e.g. "1 done, 2 перенести"), match against the most recent unresolved entry, apply via `mcp__notion__API-patch-page`, update the file. See `morning-ritual` and `evening-review` SKILL.md for protocol.

## Failure modes

- Notion auth expired → react with `⚠️`, reply «Notion auth expired. Run `/cgtd-reauth notion`». Do NOT silently drop.
- Drive upload failed → still create Inbox entry without attachment link, mention in body «(attachment upload failed)».
- Drive not configured → create Inbox entry without Drive link; body notes the attachment was received.
- Config exists but `notion.capture.db_id` empty (incomplete init) → fall back to pre-init guard behavior.
