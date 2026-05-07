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

## Email watermark

Before fetching Gmail, load the seen-ID sets from `/data/email-watermarks.json`:

    {"email@gmail.com": ["msg_id_1", "msg_id_2"]}

- If the file is absent or cannot be parsed (malformed JSON): treat all accounts as having no watermark (first-run fallback). Continue without aborting.
- For each account, extract its list of seen IDs (default empty list if key absent). Store in memory as `watermark[email]`.

## Sources (per account in `config.google.accounts[]`)

For each `email` in `accounts`:

- **Gmail primary (two-step fetch):**
  1. **Header scan**: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h -category:promotions -category:social"`. This returns message IDs, subjects, senders, and dates — enough to classify.
  - After the header scan: filter out any message whose ID is already in `watermark[email]`. Only pass the remaining (unseen) messages to step 2 (full content fetch) and to classification.
  2. **Full content fetch**: call `mcp__google-workspace__get_gmail_message_content` (or `get_gmail_messages_content_batch`) with `format: "full"` **only** for messages classified as potentially actionable from step 1. Fetch in batches of **max 10** messages per call.
- **Gmail promo sweep**: `mcp__google-workspace__search_gmail_messages user_google_email=<email>` with `query="newer_than:24h category:promotions"`. Header scan only; fetch full content only for promos that pass the deadline keyword check.
- Calendar today + 2 days: `mcp__google-workspace__get_events user_google_email=<email>`.

Merge across accounts. Dedupe by `message_id` (Gmail) and `event_id` (Calendar). Tag the source account in Telegram output **only when ambiguous** (same title from two accounts).

Also fetch Notion Next Actions + Inbox via `mcp__notion__search` — for dedup only.

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

**Notion date format:** When creating pages with a Date property, always use the expanded key format:
- `"date:Date:start": "YYYY-MM-DD"` (required)
- `"date:Date:end": "YYYY-MM-DD"` (optional, for ranges such as hotel stays)
Do NOT use `"Date": "YYYY-MM-DD"` — this causes a validation error.

## Dedup

`mcp__notion__search` by subject/thread_id with `data_source_url` before create.

## Output (one Telegram message via `mcp__plugin_telegram_telegram__reply` to `config.telegram.chat_id`)

- Silent if nothing added and nothing urgent.
- One summary «➕ N в Next Actions, M в Inbox» with titles/dates/links.
- Separate 🚨 message for urgent items: what / when / source.

## Watermark write (per account, after processing)

After processing each account's messages:

1. Collect **all message IDs returned by `search_gmail_messages`** for this account in this run — including those skipped as duplicates. These are the IDs from the header scan, not just actionable ones.
2. Write to `/data/email-watermarks.json`:
   - Read the current file (or start with `{}`).
   - Set `watermarks[account_email]` to the list of all IDs from this run.
   - Write the full dict back. Do not touch other accounts' keys.
3. If no messages were found for an account, write `[]` for that account's key (clears stale IDs from the previous run).
4. If the account returned an auth or network error, skip watermark update for that account (preserve its existing key).
5. If the watermarks file was unreadable on load (parse error): overwrite it cleanly with the data from this run.

## Failure modes

- **Per-account Google auth failure**: if one account returns `invalid_grant`, do NOT exit. Instead:
  1. Send Telegram: «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`».
  2. Skip that account, continue processing remaining accounts in `config.google.accounts[]`.
  3. After all accounts are processed: if at least one account succeeded → log cron run as `degraded` (not `fail`). If all accounts failed → log `fail`.
- **Notion auth failure**: if Notion MCP returns an auth error → send Telegram «Notion auth истёк. Запусти `/cgtd-reauth notion`». Skip all Notion writes. Continue Gmail/Calendar processing. Urgent 🚨 pings still fire (they are Telegram messages, not Notion writes). Log as `degraded`.
- Gmail/Calendar timeout → continue with remaining sources; silent if all unavailable; log `fail` with the error.
