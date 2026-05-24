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
6. **Approval required tasks.** Read `/data/tasks-pending.json`. For each entry, show task title + NA titles. Propose a date/time slot for each NA based on Eisenhower priority (Priority field + Due proximity):
   - Q1 (high priority + Due ≤ 3d) → slot today or tomorrow
   - Q2 (high priority, no urgent deadline) → next focus block this week
   - Q3 (normal/low + Due ≤ 3d) → short slot today/tomorrow
   - Q4 (low, no deadline) → Someday/Maybe, no date yet
   Ask: «Одобряешь расписание? [да / подправлю]». On approval → PATCH each NA with proposed Date. Remove entry from `tasks-pending.json`.
7. **Flagged tasks.** Read `/data/tasks-flags.json`. Group by flag_reason and surface concisely:
   - `no_na`: «нет NA — нужно добавить или архивировать»
   - `deadline_soon`: «дедлайн через N дней, нет прогресса»
   - `stalled`: «завис — нет активности >7 дней»
   - `overdue`: «просрочен»
   Ask user to confirm action or ignore.
8. **Closing line** in `config.user.locale`. Examples: en «day mapped, let's go», ru «поехали, день размечен», de «Tagesplan steht».

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

### Pre-slotting checks

Before building the plan:
1. **Check current local time** (`TZ=$(jq -r .user.timezone /data/config.json) date`). Never propose slots in the past. Only slot from now + ~15 min buffer forward.
2. **Conflict detection.** Sort all datetime NAs for today by start time. Walk the list — if any NA's start < previous NA's end → conflict. De-conflict by reordering or deferring lower-priority items. Never present overlapping slots as a valid plan.
3. **Human needs.** Always reserve: lunch block (timing per user context: home ~14:30–15:00, work ~12:20–13:00) and at least one 15–20 min rest buffer in the afternoon. If existing NAs leave no room for breaks, flag this explicitly before adding more.
4. **Weekend start time.** On Saturday/Sunday, user typically starts doing tasks after lunch (~15:00). Don't slot household or admin NAs in the morning on weekends unless explicitly requested.
5. **Calendar↔NA sync.** After fetching today's NAs, cross-reference with Google Calendar events. If an NA and a Calendar event match (same title/topic, same day), they must have identical times. If they differ → sync Calendar to match NA (or vice versa, using Calendar as the source of truth if it was set by the user directly). When rescheduling a timed Calendar event, always ask for the new time — never convert to all-day silently.
6. **Background tasks.** Read `/data/background-tasks.json`. For entries with `finish_slotted = false`, create and slot a finish NA. For entries where `finish_slot_end` is in the past, remove the entry.

### Realistic time estimation

Do not assume all NAs take 20–30 min. Look for multi-step indicators in the title:
- Tasks with prep + execution + cleanup (3D printing, cooking, painting) → allocate full realistic duration
- Physical cleaning tasks → typically 45–90 min
- Admin/digital tasks (booking, forms, listings) → 15–30 min each
- If uncertain, err on the side of more time rather than less

### Background task pattern (async NAs)

Some NAs have a "launch → machine runs → finish" structure. Detect these by title keywords:
- Laundry (стирка, постирать): put in machine ~10 min → machine runs 60–90 min → hang dry ~15 min
- 3D printing (печать, напечатать): prep + clean resin + load model ~60 min → printer runs 3–6 h → wash + post-process ~30 min
- Cooking (варить, тушить, запекать): prep → oven/stove runs → finish

**When a background task is detected:**
1. Slot the PREP phase as the NA's start time (update existing NA date).
2. Estimate the background duration and compute finish time.
3. Create a NEW NA in Notion for the finish step (e.g. "Постобработка — [description]") with the estimated finish time. Link it to the same Task relation if one exists.
4. Write an entry to `/data/background-tasks.json` (see schema below).
5. Fill the background window with other contextually compatible NAs — present this as a clean schedule. Do NOT annotate slots with "принтер работает фоном" or similar — track it internally only.
6. The user sees only: prep slot + normal tasks during background + finish slot.

**`/data/background-tasks.json` schema:**
```json
[
  {
    "id": "unique-id",
    "type": "3d_print | laundry | cooking | other",
    "description": "human-readable label",
    "prep_na_id": "notion-page-id of the launch NA",
    "launched_at": "ISO datetime when background phase starts",
    "estimated_finish": "ISO datetime when finish step can begin",
    "finish_action": "what needs to be done at finish",
    "finish_na_id": "notion-page-id of the finish NA (null if not created yet)",
    "finish_slotted": true,
    "finish_slot_start": "ISO datetime",
    "finish_slot_end": "ISO datetime"
  }
]
```

**At each planning session (morning-ritual, evening-review):**
1. Read `/data/background-tasks.json`.
2. For each entry where `finish_slotted = false`: create finish NA in Notion and slot it into the next available window. Update the entry.
3. For each entry where `finish_slotted = true` and `finish_slot_end` is in the past: remove the entry (task complete).
4. If `estimated_finish` has passed but finish NA still shows "Not started" in Notion → surface as a reminder in the plan.

### Context-stacking for errands

When slotting from Someday/Maybe or aligning errands with anchored trips:
- **Trip-based grouping.** If an anchored NA implies a trip («поездка в магазин»), sweep Someday/Maybe for compatible items («купить полку», «забрать посылку»).
- **Location/tool grouping.** Batch NAs that share a context: all-computer tasks together, all-balcony tasks together, all-errands-outside together. Don't interleave physical and digital arbitrarily.
- **Someday/Maybe scan.** Always scan S/M NAs for items compatible with today's context (location, tools at hand, available time windows). Slot the best fits using Eisenhower (Q1→Q2→Q3→Q4). Don't just list them — propose a concrete slot.
- **Parallel slotting.** Multiple errands may share one time slot if contextually compatible OR each <15 min.
- **Format.** Flat list, same start–end as the anchor. No nested bullets. NA = calendar; parallel items = same timestamp.

## Failure modes

- Notion MCP unauthenticated → skip Notion sections, still send Gmail + Calendar + rough plan.
- google-workspace `invalid_grant` for an account → log `fail` with `google_auth_expired:<email>`, ping Telegram «run /cgtd-reauth», exit.
