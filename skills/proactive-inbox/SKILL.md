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

## MCP guard

Before any API call, attempt `mcp__google-workspace__list_calendars user_google_email=<config.google.accounts[0]>`.

- If the tool returns a **tool-not-found / not-available error** (i.e. the MCP server is not loaded in this session — distinct from an auth error or API error):
  1. Try `mcp__plugin_telegram_telegram__reply chat_id=<config.telegram.chat_id>` with:
     > ⚠️ Кроны не работают: MCP-серверы не загрузились в этой сессии. Запусти channel-сессию:
     > ```
     > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
     > ```
  2. `cron-log.sh fail "$RID" "mcp_unavailable: start channel session"`. Exit.
- Auth error (OAuth URL in response) → continue normally; auth failures are handled per-account below.

## Sources (per account in `config.google.accounts[]`)

For each `email` in `accounts`:

- Gmail primary: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h -category:promotions -category:social"`. Includes read mail.
- Gmail promo sweep: same tool, `query="newer_than:24h category:promotions"`. See "Promo deadline scan" below.
- Calendar today + 2 days: `mcp__google-workspace__get_events user_google_email=<email>`.

Merge across accounts. Dedupe by `message_id` (Gmail) and `event_id` (Calendar). Tag the source account in Telegram output **only when ambiguous** (same title from two accounts).

Also fetch Notion Next Actions + Inbox via `mcp__notion__notion-search` — for dedup only.

## Gmail classification

1. Actionable from human / deadline / invoice with due / meeting RSVP → **Next Actions** with Date.
2. Booking/ticket/confirmation (cinema, concert, hotel, flight, train, restaurant) → always fetch the **full email body** (`format="full"`), not just metadata. EVENTIM and similar ticketing services always include date, time, and venue in the body even when absent from the subject line. Parse date + venue from body, then:
   - Concrete date found → **Next Actions** with Date. Always use `Date.start` + `Date.end` when time is known. Derive end time: flight = departure + arrival, train = same, cinema/concert = start + runtime/end time, restaurant = reservation + ~1.5h if no end given, hotel = check-in + check-out. Only `Date` alone when no time at all.
   - No date found after reading full body → **Inbox** with note «дата не найдена — уточнить». Never route to Notes.
3. Transactional without action (statements, receipts, subscriptions) → ignore.
4. Newsletters → ignore unless deadline-bound (see Promo deadline scan).

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

**Status–Date invariant.** A page with Status=`Not started` MUST have a Date. Apply this 5-step inference chain before deciding on status:
1. Implicit phrases in text (per `feedback_implicit_dates.md`).
2. Contextual heuristics (per `feedback_contextual_deadlines.md`): daily-use repair 1–2 weeks, seasonal 3–4 weeks, health/admin 2 weeks, gifts = event date − buffer, package/storage pickup = email date + pickup window − 1 day, marketplace reply (Kleinanzeigen, eBay) = 1–2 days.
3. Full body read: if not done yet for this email, call `get_gmail_message_content format="full"` and re-parse.
4. Cross-Notion lookup: if the action is tied to a named event, search NA+Tasks by event title → subtract domain lead time (transport tickets −1–2 months, accommodation −2–3 months, gift −1–2 weeks, outfit −1 week).
5. If date still unknown → **Inbox** with note «дата не найдена — уточнить». Never to `Someday/Maybe`.

`Someday/Maybe` is the ONLY status that may have no Date.

Ambiguous phrases ("soon", "asap" without time) → Inbox + flag in ⚠️.

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

**Notion date format:** When creating pages with a Date property, always use the expanded key format:
- `"date:Date:start": "YYYY-MM-DD"` (required)
- `"date:Date:end": "YYYY-MM-DD"` (optional, for ranges such as hotel stays)
Do NOT use `"Date": "YYYY-MM-DD"` — this causes a validation error.

## Dedup

`mcp__notion__notion-search` by subject/thread_id with `data_source_url` before create.

## Output (one Telegram message via `mcp__plugin_telegram_telegram__reply` to `config.telegram.chat_id`)

- Silent if nothing added and nothing urgent.
- One summary «➕ N в Next Actions, M в Inbox» with titles/dates/links.
- Separate 🚨 message for urgent items: what / when / source.

## Failure modes

- **Per-account Google auth failure**: if one account returns `invalid_grant`, do NOT exit. Instead:
  1. Send Telegram: «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`».
  2. Skip that account, continue processing remaining accounts in `config.google.accounts[]`.
  3. After all accounts are processed: if at least one account succeeded → log cron run as `degraded` (not `fail`). If all accounts failed → log `fail`.
- **Notion auth failure**: if Notion MCP returns an auth error → send Telegram «Notion auth истёк. Запусти `/cgtd-reauth notion`». Skip all Notion writes. Continue Gmail/Calendar processing. Urgent 🚨 pings still fire (they are Telegram messages, not Notion writes). Log as `degraded`.
- Gmail/Calendar timeout → continue with remaining sources; silent if all unavailable; log `fail` with the error.
