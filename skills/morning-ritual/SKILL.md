---
name: morning-ritual
description: Morning brief — Gmail 24h, today's calendar, overdue Next Actions, time-blocked plan for today around the user's rhythm preset. One Telegram message, awaits user approval.
---

# Morning ritual

Invoked by cron `cgtd-${install_id}-morning-ritual` (default `30 8 * * *`) or manually via `/morning`.

## Pre-flight

Read `/data/config.json`. Required: `user.{locale,timezone}`, `notion.next_actions_id`, `google.accounts[]`, `schedule.*`, `telegram.chat_id`.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start morning-ritual)
/app/bin/cron-log.sh lock morning-ritual || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## MCP guard

Before any API call, attempt `mcp__google-workspace__list_calendars user_google_email=<config.google.accounts[0]>`.

- If the tool returns a **tool-not-found / not-available error** (MCP server not loaded in this session):
  1. Try `mcp__plugin_telegram_telegram__reply chat_id=<config.telegram.chat_id>` with:
     > ⚠️ Утренний бриф не запустился: MCP-серверы не загрузились. Запусти channel-сессию:
     > ```
     > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
     > ```
  2. `cron-log.sh fail "$RID" "mcp_unavailable: start channel session"`. Exit.
- Auth error (OAuth URL in response) → continue; handled in Failure modes.

## Message structure

1. **Overdue NA sweep.** Enumerate ALL Next Actions with `Date < today` AND Status ∉ {Done, Cancelled}. No keyword shortcuts. Dedicated section.
2. **Today's anchors** (same weight, do not move):
   - Calendar events today across all `config.google.accounts[]`.
   - NA with `Date.start = today` (any `is_datetime`). User already scheduled them.
3. **Gmail 24h.** Skip promo/social, only actionable/decision items. Cross-account.
4. **TODAY PLAN with time blocks.** Fill around anchors per `config.schedule.weekday_blocks` (or weekend rule on Sat/Sun). Propose slots with NA tokens for approval. Do NOT re-slot anchored NA. Write approved items via `mcp__notion__notion-update-page` only after user confirms.
5. **Free-slot reserve.** Pull from NA with `Status=Someday/Maybe AND no Date`, prioritized by Eisenhower (Q1→Q2→Q3→Q4).

   **Weekend day rule:**
   - **Saturday** → propose only leisure/hobby items from Someday/Maybe. Household errands, admin tasks (cleaning, repairs, settings, buying supplies) are NOT proposed on Saturday.
   - **Sunday** → household and admin tasks only (cleaning, repairs, configuration, buying supplies). Leisure/hobby items are deprioritized.
6. **Closing line** in `config.user.locale`. Examples: en «day mapped, let's go», ru «поехали, день размечен», de «Tagesplan steht».

## Awaiting user approval

Write a JSON line to `/data/pending-reviews.jsonl`:
```
{"cron_id":"morning-ritual","ts":"<iso>","items":[{"na_id":"...","title":"...","start":"...","end":"..."}]}
```
TTL 6h. When the user replies in Telegram («1, 3 ok; 2 перенести»), the inbox-router skill matches against this entry, applies via `notion-update-page`, removes the entry. On SessionStart catch-up, entries older than TTL are dropped silently.

## Slotting

Use `config.schedule.rhythm_preset`:

- **flex** — only morning brief + evening review fire; NA slotting is suggestive, not enforced. Free-form day.
- **9to5** — focus blocks 09:00–12:00 + 13:00–17:00; personal evenings; weekends rest.
- **shift** — user provides custom blocks during init.
- **custom** — read `config.schedule.weekday_blocks[]` directly.

For each focus block, label slots `"work task"` (don't ask the user what they're working on, don't fill a project name — see `feedback_work_task_default.md`-style memory if user adds one). Personal NA → evening blocks. Admin → short evening or weekend afternoon.

### Context-stacking for errands

When slotting from Someday/Maybe or aligning errands with anchored trips:
- **Trip-based grouping.** If an anchored NA implies a trip («поездка в магазин»), sweep Someday/Maybe for compatible items («купить полку», «забрать посылку»).
- **Parallel slotting.** Multiple errands may share one time slot if contextually compatible OR each <15 min.
- **Format.** Flat list, same start–end as the anchor. No nested bullets. NA = calendar; parallel items = same timestamp.

## Failure modes

- Notion MCP unauthenticated → skip Notion sections, still send Gmail + Calendar + rough plan.
- google-workspace `invalid_grant` for an account → log `fail` with `google_auth_expired:<email>`, ping Telegram «run /cgtd-reauth», exit.
