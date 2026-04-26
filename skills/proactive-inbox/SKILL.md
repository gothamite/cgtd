---
name: proactive-inbox
description: Scan Gmail (last 24h) + Calendar (today + 2 days) across all configured Google accounts, classify and route actionable items to Notion Next Actions / Inbox, ping Telegram on urgent deadlines.
---

# Proactive inbox scan

Invoked by cron `cgtd-${install_id}-proactive-inbox` (default `13 8-20/2 * * *`) or manually via `/inbox` from Telegram.

## Pre-flight

Read `/data/config.json`. Required: `notion.{inbox,next_actions}_id`, `google.accounts[]`, `telegram.chat_id` (if Telegram enabled). If missing → log `fail` with `config_incomplete`, exit.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start proactive-inbox)
/app/bin/cron-log.sh lock proactive-inbox || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## Sources (per account in `config.google.accounts[]`)

For each `email` in `accounts`:

- Gmail primary: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h -category:promotions -category:social"`. Includes read mail.
- Gmail promo sweep: same tool, `query="newer_than:24h category:promotions"`. See "Promo deadline scan" below.
- Calendar today + 2 days: `mcp__google-workspace__get_events user_google_email=<email>`.

Merge across accounts. Dedupe by `message_id` (Gmail) and `event_id` (Calendar). Tag the source account in Telegram output **only when ambiguous** (same title from two accounts).

Also fetch Notion Next Actions + Inbox via `mcp__notion__notion-search` — for dedup only.

## Gmail classification

1. Actionable from human / deadline / invoice with due / meeting RSVP → **Next Actions** with Date.
2. Booking/ticket/confirmation with concrete date (cinema, concert, hotel, flight, restaurant) → **Next Actions** with Date. Hotels/trips: `Date.start` + `Date.end`.
3. Booking without action date → **Inbox**.
4. Transactional without action (statements, receipts, subscriptions) → ignore.
5. Newsletters → ignore unless deadline-bound (see Promo deadline scan).

### Promo deadline scan

Scan `category:promotions` for time-bound offers within the next **5 days**. Surface ONLY if a concrete deadline keyword is present.

Deadline keywords (EN/DE/RU, case-insensitive):
- "last day", "ends today", "only today", "ends tonight", "expires today", "final hours"
- "only until", "valid until", "ends [day/date]", "sale ends"
- "letzte Tage", "letzter Tag", "nur bis", "endet heute/morgen", "gültig bis"
- «последний день», «только сегодня», «акция до», «истекает», «спешите до»
- Specific dates parseable per `feedback_implicit_dates`.

Routing:
- Promo with concrete deadline ≤5 days → **Inbox**, deadline mentioned in body. Surface in summary section «🛍 Promo с дедлайном».
- Promo with deadline >5 days OR vague → ignore.
- Promo without deadline → ignore.

Do NOT 🚨 promo items.

### Priority signals (create Notion entry even if email is read)

- Payment: invoice, due, bill, payment due, счёт, оплата, перевод, transfer.
- Deadline: respond by, reply by, by [date], deadline, дедлайн, до [дата].
- RSVP: RSVP, invitation, confirm attendance, приглашение, подтвердите.

If signal present and item not in NA/Inbox → create.

### Date parsing

Apply `/data/memory/feedback_implicit_dates.md` + `feedback_contextual_deadlines.md`. Ambiguous phrases ("soon", "asap" without time) → Inbox + flag in ⚠️.

## Calendar

- New invitation needing RSVP → ping + optional NA «Reply: [title]» with event date.
- Today/tomorrow reschedule or cancel → ping.
- Normal confirmed events → ignore.

## Urgency (🚨 separate Telegram message)

Triggers:
- "respond by EOD", "confirm within X hours", "срочно", "asap", "истекает сегодня".
- Hard deadline <24h.
- New event/deadline within 24h.
- NA conflict: two overlapping items in next 48h.

Do NOT 🚨 priority-signal items alone.

## Dedup

`mcp__notion__notion-search` by subject/thread_id with `data_source_url` before create.

## Output (one Telegram message via `mcp__plugin_telegram_telegram__reply` to `config.telegram.chat_id`)

- Silent if nothing added and nothing urgent.
- One summary «➕ N в Next Actions, M в Inbox» with titles/dates/links.
- Separate 🚨 message for urgent items: what / when / source.

## Failure modes

- Notion MCP unauthenticated → skip Notion writes silently, still 🚨 ping for urgent, mark log `ok` (degraded mode).
- google-workspace returns `invalid_grant` for an account → log `fail` with `google_auth_expired:<email>`, send Telegram «Google auth for <email> expired, run `/cgtd-reauth <email>`», exit. See `cgtd-reauth/SKILL.md`.
- Gmail/Calendar timeout → continue with remaining sources; silent if all unavailable; log `fail` with the error.
