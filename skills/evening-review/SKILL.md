---
name: evening-review
description: Evening review of today's Next Actions + 24h digest (Gmail / Calendar across all accounts / Notion changes). One Telegram message, awaits user replies on NA status.
---

# Evening review + digest

Invoked by cron `cgtd-${install_id}-evening-review` (default `28 21 * * *`) or manually via `/evening`.

## Pre-flight

Read `/data/config.json`. Required: `notion.next_actions_id`, `google.accounts[]`, `telegram.chat_id`.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start evening-review)
/app/bin/cron-log.sh lock evening-review || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## Message structure

1. **TODAY REVIEW.** Next Actions with `Date=today` where Status ≠ Done/Cancelled. List each (with NA id), ask «What about X? — Done / Move to tomorrow / Cancel / Continue tomorrow». Skip section if all closed.
2. **Digest 24h.** Across all `config.google.accounts[]`: Gmail (actionable/decision, skip promo/social), Calendar events that passed today + tomorrow's schedule, Notion Inbox + NA changes.
3. **Control line.** Brief health: last-ok timestamps for the four crons via `cron-log.sh last-ok`.

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

- Notion MCP unauthenticated → skip TODAY REVIEW + Notion sections, still send Gmail/Calendar digest.
- google-workspace `invalid_grant` → log fail, ping for /cgtd-reauth, exit.
