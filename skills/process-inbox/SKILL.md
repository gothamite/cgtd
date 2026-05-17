---
name: process-inbox
description: Classify entries in Notion Inbox and route to Next Actions / Tasks / Notes, then archive originals. Cron job (default 20:57); also runs on demand via /inbox or «разбери инбокс».
---

# Process Notion Inbox

Invoked by cron `cgtd-${install_id}-process-inbox` (default `57 20 * * *`) or manually via `/inbox`.

## Pre-flight

Read `/data/config.json`. Required: `notion.{inbox,next_actions,tasks,notes}_id`, `telegram.chat_id`. If `notion.enabled=false` → log `ok` (no-op), exit.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start process-inbox)
/app/bin/cron-log.sh lock process-inbox || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## MCP guard

Before any API call, attempt `mcp__notion__notion-search query=""`.

- If the tool returns a **tool-not-found / not-available error** (MCP server not loaded in this session):
  1. Try `mcp__plugin_telegram_telegram__reply chat_id=<config.telegram.chat_id>` with:
     > ⚠️ Обработка Inbox не запустилась: MCP-серверы не загрузились. Запусти channel-сессию:
     > ```
     > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
     > ```
  2. `cron-log.sh fail "$RID" "mcp_unavailable: start channel session"`. Exit.
- Auth error → continue; handled in Failure modes.

## Procedure

1. Query Inbox via `mcp__notion__notion-query-database-view` (fallback: `mcp__notion__notion-search` on `config.notion.inbox_id`).
2. For each entry, extract implicit date/deadline per `/data/memory/feedback_implicit_dates.md` + `feedback_contextual_deadlines.md`.

   **Status–Date invariant.** A page with Status=`Not started` MUST have a Date. Apply this inference chain before deciding on status:
   1. Implicit phrases in text (per `feedback_implicit_dates.md`).
   2. Contextual heuristics (per `feedback_contextual_deadlines.md`).
   3. Cross-Notion lookup: if the action is tied to a named event, search NA+Tasks by event title → subtract domain lead time (transport tickets −1–2 months, accommodation −2–3 months, gift −1–2 weeks, outfit/costume −1 week).
   4. If date still unknown → route to Inbox with note «дата не найдена — уточнить». Never to `Someday/Maybe`.
   `Someday/Maybe` is the ONLY status that may have no Date.

3. **Dedup check.** Before creating in destination, `mcp__notion__notion-search` the target data source for the entry's title — fuzzy match (lemmatize, drop filler words). If a candidate duplicate exists AND is not Done/Cancelled:
   - Exact/near-exact match → skip create; archive the Inbox entry; mention in ⚠️ «duplicate, archived original, existing: [link]».
   - Partial match → don't auto-skip; surface in ⚠️ with both links, ask user via Telegram («дубликат X? [a] объединить / [b] оставить обе / [c] отменить»).
   - Duplicate exists but Done/Cancelled → proceed with create.
4. Classify:
   - **(a) atomic action with date** → `config.notion.next_actions_id`, Status=`Not started`, Date.start=extracted. If the event has a known end time, set Date.end as well (Next Actions = time-blocked calendar slot).
   - **(a') atomic without time signal** → Next Actions, Status=`Someday/Maybe`. Apply contextual inference first: daily-use repair 1–2 weeks, seasonal clothing 3–4 weeks before peak, health/admin 2 weeks, gifts = event date − buffer, pure-want → Someday/Maybe.
   - **(a'') booking/ticket/event without explicit date** → before routing, search the originating Gmail message body (if source is known) for the date: call `get_gmail_message_content format="full"` on the source thread. If date found → rule (a) with Date. If still not found → ⚠️ Clarify with note «дата не найдена — уточнить». Never route to Notes.
   - **(b) multi-step / project** (several verbs, "проект", "organize", "prepare for X") → `config.notion.tasks_id`, subtasks in body, deadline if present.
   - **(c) informational** (reference, link, quote, idea, contact, recipe, article, fact — no event, no action) → `config.notion.notes_id` with Category + 2–4 Tags + URL, Source=Telegram.
   - Create destination via `mcp__notion__notion-create-pages`.
5. After creating destination → trash the Inbox entry: PATCH `/pages/{id}` with `{"in_trash": true}` (Notion trash — 30-day recovery buffer). Do NOT move to an archive page.
6. Ambiguous entries → leave in Inbox, collect for ⚠️ section.

## Attachments

If an Inbox entry references a file URL hosted outside Drive (e.g. inline-uploaded by inbox-router), the file should already be in `config.google.drive_inbox_folder_id` on the **primary** account. Skill itself does no Drive uploads — that's inbox-router's job. Just preserve the link in the destination page body.

## Idempotency

If the skill is killed mid-run and retries, a second pass sees only not-yet-trashed entries (Notion excludes trashed pages from query results). Already-processed items are in trash. No further dedup needed.

## Output (one Telegram message)

«📥 Inbox processed: N entries» + sections:
- **Next Actions** (with dates, links)
- **Someday** (titles, links)
- **Tasks** (titles, links)
- **Notes** (with Category, links)
- **⚠️ Clarify** — ambiguous ones with 2–3 options.

Silent if Inbox empty.

## Failure modes

- Notion MCP unauthenticated → silent exit, log `ok`.
- Partial failure mid-batch: archive each item right after creating its destination so a crash leaves processed items consistent.
