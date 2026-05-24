---
name: evening-review
description: Evening review of today's Next Actions + 24h digest (Gmail / Calendar across all accounts / Notion changes). One Telegram message, awaits user replies on NA status.
---

# Evening review + digest

Invoked by cron `cgtd-${install_id}-evening-review` (default `28 21 * * *`) or manually via `/evening`.

## Pre-flight

Read `/data/config.json`. Required: `telegram.chat_id`. Everything else degrades gracefully — see Failure modes.

**Google optional:** check `config.google.enabled`. If `false` or `config.google.accounts` is empty → skip Gmail and Calendar sections. Still run Notion sections.

## Runtime role resolution

Before any Notion query:
```
actions_id       = notion.actions.db_id → if same_as_capture or empty: notion.capture.db_id
actions_name     = notion.actions.db_name → fallback: notion.capture.db_name
status_field     = notion.actions.fields.status → null if not set
status_open      = notion.actions.fields.status_open → fallback: "Not started"
status_done      = notion.actions.fields.status_done → fallback: "Done"
status_cancelled = notion.actions.fields.status_cancelled → fallback: "Cancelled"
date_field       = notion.actions.fields.date → null if not set
projects_id      = notion.projects.db_id (resolved) → null if not set

calendar_source      = config.gtd.calendar_source  ("google" | "notion" | "both" | "none")
notion_calendar_id   = notion.calendar.notion_db_id  (null if not applicable)
google_calendars     = notion.calendar.google_calendars  ([] if not applicable)
calendar_integration = config.gtd.calendar_integration
```

If `status_field` is null → fetch all items without status filter; sort by date.
If `date_field` is null → TODAY REVIEW shows ALL open items instead of date-filtered ones.
If `config.gtd.unmappable_warning: true` → fetch all items without any filter; label «⚠️ схема не распознана — показываю всё».

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start evening-review)
/app/bin/cron-log.sh lock evening-review || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## MCP guard

Before any API call, attempt `mcp__google-workspace__list_calendars user_google_email=<config.google.accounts[0]>`.

- If the tool returns a **tool-not-found / not-available error** (MCP server not loaded in this session):
  1. Try `mcp__plugin_telegram_telegram__reply chat_id=<config.telegram.chat_id>` with:
     > ⚠️ Вечерний обзор не запустился: MCP-серверы не загрузились. Запусти channel-сессию:
     > ```
     > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
     > ```
  2. `cron-log.sh fail "$RID" "mcp_unavailable: start channel session"`. Exit.
- Auth error (OAuth URL in response) → continue; handled in Failure modes.

## Message structure

1. **TODAY REVIEW.** 
   - If `date_field` is set: items in `actions_id` with `date_field = today` where status ≠ `status_done` / `status_cancelled`. List each, ask «What about X? — Done / Move to tomorrow / Cancel / Continue tomorrow».
   - If `date_field` is null: show ALL open items (status ≠ done/cancelled, or all if `status_field` is null too). Ask which were done today, which carry over. This is the full end-of-day review for users with a simple undated list — never skip it entirely.
2. **Pending approvals.** Read `/data/tasks-pending.json`. If non-empty AND `projects_id` is set: show each project + its linked actions. Propose date/time for each action using priority heuristics. Ask: «Одобряешь? [да / подправлю]». On approval → PATCH actions with proposed Date. Remove from `tasks-pending.json`. Skip if `projects_id` is null.
3. **Flagged projects.** Read `/data/tasks-flags.json`. If non-empty AND `projects_id` is set: surface grouped by reason. Skip if file absent or `projects_id` null.
4. **Digest 24h.**
   - **Gmail** (if `config.google.enabled`): actionable/decision items, skip promo/social.
   - **Calendar — passed today + tomorrow's schedule:**
     - `calendar_source = "google"` or `"both"`: `mcp__google-workspace__get_events` for today + tomorrow across `google_calendars`.
     - `calendar_source = "notion"` or `"both"`: query `notion_calendar_id` for today + tomorrow.
     - `calendar_source = "none"`: skip Calendar section.
   - Inbox + actions changes (new items added today) regardless of Google status.
5. **Control line.** Brief health: last-ok timestamps for the crons via `cron-log.sh last-ok`.

Silent if everything is empty.

## Fetching today's items

`API-post-search` cannot filter by Date field. Use `API-post-search` with query = today's ISO date (e.g. `"2026-04-26"`) against `actions_id` — semantic search reliably surfaces entries with date=today. Do NOT rely on `created_date`. If `date_field` is null, skip this entirely.

## Awaiting user decisions

Persist proposal to `/data/pending-reviews.jsonl`:
```
{"cron_id":"evening-review","ts":"<iso>","items":[{"na_id":"...","title":"...","date":"today"}]}
```

When user replies in Telegram, inbox-router matches against the most recent `evening-review` entry whose items aren't all resolved, applies via `API-patch-page`, removes the entry.

TTL 12h. On SessionStart catch-up, items not acted on get the default action: **«move to tomorrow»** (shift Date +1, keep status), silently.

## Failure modes

- Notion MCP unauthenticated → skip TODAY REVIEW + Notion sections; send Gmail/Calendar digest if Google enabled. If neither available → send «⚠️ Notion недоступен, Google не подключён — вечерний обзор пуст. Запусти `/cgtd-reauth notion`». Log `degraded`.
- **[Google only]** `invalid_grant` for an account → send Telegram «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`». **Do NOT exit** — continue with remaining accounts + full Notion review (TODAY REVIEW, Approval required, Flagged tasks). Log `degraded`.
