---
name: evening-review
description: Evening review of today's Next Actions + 24h digest (Gmail / Calendar across all accounts / Notion changes). One Telegram message, awaits user replies on NA status.
---

# Evening review + digest

Invoked by cron `cgtd-${install_id}-evening-review` (default `28 21 * * *`) or manually via `/evening`.

## Pre-flight

Read `/data/config.json`. Required: `notion.next_actions_id`, `telegram.chat_id`.

**Google optional:** check `config.google.enabled`. If `false` or `config.google.accounts` is empty → skip Gmail and Calendar sections. Still run Notion sections.

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

1. **TODAY REVIEW.** Next Actions with `Date=today` where Status ≠ Done/Cancelled. List each (with NA id), ask «What about X? — Done / Move to tomorrow / Cancel / Continue tomorrow». Skip section if all closed.
2. **Approval required tasks.** Read `/data/tasks-pending.json`. If non-empty, show each task + its NAs. Propose Eisenhower-based date/time for each NA:
   - Q1 (high + Due ≤ 3d) → tomorrow or day after
   - Q2 (high, no urgent deadline) → next focus block
   - Q3 (normal/low + Due ≤ 3d) → short slot this week
   - Q4 (low, no deadline) → Someday/Maybe
   Ask: «Одобряешь? [да / подправлю]». On approval → PATCH NAs with proposed Date. Remove from `tasks-pending.json`.
3. **Flagged tasks.** Read `/data/tasks-flags.json`. If non-empty, surface grouped by reason. Ask user to confirm action or ignore.
4. **[Google only] Digest 24h.** If `config.google.enabled`: Gmail (actionable/decision, skip promo/social) + Calendar events that passed today + tomorrow's schedule. Notion Inbox + NA changes regardless of Google status.
5. **Control line.** Brief health: last-ok timestamps for the four crons via `cron-log.sh last-ok`.

Silent if everything is empty.

## Fetching today's NA

`notion-search` cannot filter by Date field. Use `notion-search` with query = today's ISO date (e.g. `"2026-04-26"`) against `config.notion.next_actions_id` — semantic search reliably surfaces entries with Date=today. Do NOT rely on `created_date`.

## Awaiting user decisions

Persist proposal to `/data/pending-reviews.jsonl`:
```
{"cron_id":"evening-review","ts":"<iso>","items":[{"na_id":"...","title":"...","date":"today"}]}
```

When user replies in Telegram, inbox-router matches against the most recent `evening-review` entry whose items aren't all resolved, applies via `notion-update-page`, removes the entry.

TTL 12h. On SessionStart catch-up, items not acted on get the default action: **«move to tomorrow»** (shift Date +1, keep status), silently.

## Failure modes

- Notion MCP unauthenticated → skip TODAY REVIEW + Notion sections; send Gmail/Calendar digest if Google enabled, otherwise log `ok` and exit.
- **[Google only]** `invalid_grant` → log fail, ping for `/cgtd-reauth`, exit.
