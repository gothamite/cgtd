---
name: inbox-router
description: Route inbound Telegram messages to Notion Inbox by default. Implements the "inbox-everything" pattern — any free-text Telegram message becomes an Inbox entry unless it matches a known command.
---

# Telegram → Notion Inbox router

Triggered when a Telegram message arrives via the `plugin:telegram` MCP. The default behavior is **drop into Inbox, no questions** — see `memory/feedback_default_inbox.md`.

## Recognized commands (handled before routing)

- `/init-cgtd` → invoke init skill
- `/cgtd-reauth <email>` → invoke cgtd-reauth skill
- `/morning` / `/утро` → invoke morning-ritual immediately
- `/evening` / `/вечер` → invoke evening-review immediately
- `/inbox` / `/разбери` → invoke process-inbox immediately
- `/status` → print last-ok timestamps for each cron job

If the message doesn't start with `/`, route to Inbox.

## Routing logic

1. Read `/data/config.json` to get `notion.inbox_id`, `telegram.chat_id`, `user.locale`.
2. Verify the message came from `config.telegram.chat_id`. If not, ignore (do not respond — the Telegram MCP allowlist should already filter, this is belt-and-suspenders).
3. **Attachments**: if the message has an image_path or attachment_file_id:
   - Download via `mcp__plugin_telegram_telegram__download_attachment` if needed.
   - Upload to the **primary** Google Drive folder (`config.google.drive_inbox_folder_id`) via `mcp__google-workspace__create_drive_file user_google_email=<primary>`.
   - Get the shareable link.
4. **Apply rule files** from `/data/memory/`:
   - `feedback_implicit_dates.md` — parse dates like «до конца зимы», "by next Friday".
   - `feedback_contextual_deadlines.md` — infer deadlines from context (seasonal, gifts, repairs).
   - `feedback_default_inbox.md` — when in doubt, drop to Inbox without asking.
5. Create a Notion Inbox row via `mcp__notion__notion-create-pages` against `config.notion.inbox_id`. Title = first 80 chars of the message, body = full text + Drive link if any.
6. React to the Telegram message with `📥` via `mcp__plugin_telegram_telegram__react`. No reply text — the reaction is enough.

## Replies to pending reviews

If the message looks like a reply to a `pending-reviews.jsonl` entry (e.g. "1 done, 2 перенести"), match against the most recent pending entry whose items aren't all resolved, apply via Notion, and update the file. See `morning-ritual` and `evening-review` SKILL.md for the matching protocol.

## Failure modes

- Notion MCP unauthenticated → react with `⚠️` and reply «Notion недоступен, сообщение не сохранено». Do NOT silently drop — user expects everything to land somewhere.
- Drive upload failed → still create Inbox entry without the attachment link, mention in body «(вложение не удалось загрузить)».
