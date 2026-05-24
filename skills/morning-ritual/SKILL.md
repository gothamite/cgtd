---
name: morning-ritual
description: Morning brief — today's anchors, overdue Next Actions, time-blocked plan for the day. Gmail/Calendar included if Google is configured. One Telegram message, awaits user approval.
---

# Morning ritual

Invoked by cron or manually via `/morning`.

## Pre-flight

Read `/data/config.json`. Required: `user.{locale,timezone}`, `telegram.chat_id`. Everything else degrades gracefully — see Failure modes.

**Google optional:** check `config.google.enabled`. If `false` or `config.google.accounts` is empty → skip all Gmail and Calendar steps silently. Proceed with Notion-only plan.

## Runtime role resolution

Before any Notion query, resolve the active DB and field names:

```
actions_id       = notion.actions.db_id → if same_as_capture or empty: notion.capture.db_id
actions_name     = notion.actions.db_name → fallback: notion.capture.db_name
status_field     = notion.actions.fields.status → fallback: "Status"
status_open      = notion.actions.fields.status_open → fallback: "Not started"
status_done      = notion.actions.fields.status_done → fallback: "Done"
status_cancelled = notion.actions.fields.status_cancelled → fallback: "Cancelled"
status_deferred  = notion.actions.fields.status_deferred → fallback: "Someday·Maybe"
date_field       = notion.actions.fields.date → fallback: "Date"
priority_field   = notion.actions.fields.priority → null if not set (skip priority section)

projects_id     = notion.projects.db_id (resolved) → null if not set
projects_name   = notion.projects.db_name → fallback: null
projects_filter = {property, value} or null

calendar_source  = config.gtd.calendar_source  ("google" | "notion" | "both" | "none")
calendar_integration = config.gtd.calendar_integration  ("unified" | "separate" | "none")
notion_calendar_id = notion.calendar.notion_db_id  (null if source ≠ "notion"/"both")
google_calendars   = notion.calendar.google_calendars  ([] if source ≠ "google"/"both")

contexts_mode   = config.gtd.contexts.mode  ("auto" | "explicit" | "none")
contexts_values = config.gtd.contexts.values  ([] if mode ≠ "explicit")
contexts_field  = config.gtd.contexts.field  (null if not stored in DB)
```

If `status_field` is null → fetch all items without status filter; sort by date only.
If `config.gtd.unmappable_warning: true` → fetch ALL items without any filter; label «⚠️ схема не распознана — показываю всё».

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start morning-ritual)
/app/bin/cron-log.sh lock morning-ritual || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## MCP guard (Google only)

**Only if Google is enabled:** attempt `mcp__google-workspace__list_calendars user_google_email=<config.google.accounts[0]>`.

- If tool returns a **tool-not-found / not-available error** (MCP server not loaded):
  1. Reply via Telegram: ⚠️ Morning brief failed: MCP servers not loaded. Start the channel session.
  2. `cron-log.sh fail "$RID" "mcp_unavailable"`. Exit.
- Auth error (OAuth URL in response) → continue; handled in Failure modes.

## Message structure

1. **Overdue sweep.** Enumerate ALL items in `actions_id` with `date_field < today` AND status ≠ `status_done` / `status_cancelled`. If `status_field` is null → filter by date only. Skip if `date_field` is null.

2. **Today's anchors** (fixed, do not move):
   - **Calendar events** — fetch based on `calendar_source`:
     - `"google"` or `"both"`: `mcp__google-workspace__get_events` for today across `google_calendars` (or all if `["*"]`).
     - `"notion"` or `"both"`: query `notion_calendar_id` for events with date = today.
     - `"none"`: skip Calendar entirely.
   - **Scheduled actions** — items in `actions_id` with `date_field.start = today`. Skip if `date_field` is null.
   - If `calendar_integration = "unified"`: deduplicate Calendar events and actions by title/topic — show each only once.

3. **[Google only] Gmail 24h.** Skip promo/social, only actionable/decision items. Omit if `config.google.enabled` is false.

4. **TODAY PLAN with time blocks.** Fill free slots around anchors per `config.schedule.weekday_blocks` (or weekend rule). Propose time slots for approval. Do NOT re-slot anchored items. Apply pre-slotting checks (time, conflicts, human needs). Write approved items via `mcp__notion__API-patch-page` only after user confirms. If `date_field` is null → skip time-blocking; go straight to step 5.

5. **Someday/Maybe — daily review and slot proposals.** This runs every day without exception.

   Query `actions_id` for ALL items with status = `status_deferred` AND date value is null or empty (not the field name — the actual stored value). These are candidates to schedule today.

   **Prioritization** (apply before presenting):
   - If `priority_field` is set → sort by it descending.
   - Else apply Eisenhower heuristic: infer urgency/importance from title + deadline hints + user narrative.
   - If `contexts_mode = "explicit"`: group by context (`contexts_field` value or inferred from title) — batch items sharing a context into the same time slot.
   - If `contexts_mode = "auto"`: silently group by inferred context before presenting (all @computer tasks together, all errands together, etc.). Don't show context labels unless natural.

   **Propose for today's free slots:**
   - Select the top N items that fit available time + context + energy (morning = high-focus, afternoon = medium, evening = routine).
   - Present as concrete proposals: «Предлагаю на сегодня: [X] в 15:00, [Y] после обеда». Don't just list — propose specific slots.
   - Items not proposed → remain in Someday/Maybe with no change.

   **If `date_field` is null** (user has no date property): show ALL open items as candidates, suggest which to tackle today, ask user to confirm. This is the primary planning output for single-list users.

6. **Pending approvals.** If `projects_id` is set and `/data/tasks-pending.json` exists: read it, show project title + linked action titles, propose date/time slots. Skip if `projects_id` is null.

7. **Flagged projects.** Read `/data/tasks-flags.json` if it exists. Surface grouped by reason. Skip if file absent or `projects_id` is null.

8. **Closing line** in `config.user.locale`.

## Awaiting user approval

Write a JSON line to `/data/pending-reviews.jsonl`:
```
{"cron_id":"morning-ritual","ts":"<iso>","items":[{"na_id":"...","title":"...","start":"...","end":"..."}]}
```
TTL 6h. When the user replies in Telegram, the inbox-router skill matches against this entry, applies via `API-patch-page`, removes the entry.

## Slotting

Use `config.schedule.rhythm_preset`:

- **flex** — suggestive slotting only; no enforced blocks.
- **9to5** — focus blocks 09:00–12:00 + 13:00–17:00; personal evenings; weekends lighter.
- **shift** — user-defined blocks from init.
- **custom** — read `config.schedule.weekday_blocks[]` directly.

For each focus block, label work slots `"work task"`. Personal NA → evening blocks. Admin → short evening or weekend afternoon.

### Pre-slotting checks

Before building the plan:
1. **Check current local time** (`TZ=$(jq -r .user.timezone /data/config.json) date`). Never propose slots in the past. Only slot from now + ~15 min buffer forward.
2. **Conflict detection.** Sort all datetime NAs for today by start time. Walk the list — if any NA's start < previous NA's end → conflict. De-conflict by reordering or deferring lower-priority items. Never present overlapping slots as a valid plan.
3. **Human needs.** Always reserve a lunch block: use `config.user.lunch_home` / `config.user.lunch_work` if set; otherwise leave a 30–45 min gap at a reasonable midday time. Also reserve at least one 15–20 min rest break in the afternoon. If existing NAs leave no room for breaks, flag this explicitly.
4. **Weekend slotting.** On weekends, apply `config.schedule.weekend_rule`: `flex` (default) = no category filtering; `rest` = prefer lighter/leisure items. If `config.user.weekend_preference` is set, follow it. Never assume a specific weekday=leisure / weekend=admin mapping without user having stated it.
5. **[Google only] Calendar↔NA sync.** If Google is enabled: after fetching today's NAs, cross-reference with Calendar events. If an NA and a Calendar event match (same title/topic, same day), times must be identical. If they differ → sync. When rescheduling a timed Calendar event, always ask for the new time — never convert to all-day silently.
6. **Background tasks.** Read `/data/background-tasks.json`. For entries with `finish_slotted = false`, create and slot a finish NA. For entries where `finish_slot_end` is in the past, remove the entry.

### Realistic time estimation

Do not assume all NAs take 20–30 min. Look for multi-step indicators in the title:
- Tasks with prep + execution + cleanup (cooking, painting, long installs) → allocate full realistic duration
- Physical cleaning tasks → typically 45–90 min
- Admin/digital tasks (booking, forms, listings) → 15–30 min each
- If uncertain, err on the side of more time rather than less

### Background task pattern (async NAs)

Some NAs have a "launch → machine runs → finish" structure. Detect by context:
- Examples: laundry (~10 min launch + 60–90 min machine + ~15 min finish), 3D printing (~60 min prep + hours of printing + ~30 min post-process), slow cooking, fermenting, drying, rendering.
- Pattern applies to any background-wait process the user describes.

**When detected:**
1. Slot the PREP phase as the NA's start time.
2. Estimate background duration; compute finish time.
3. Create a finish NA in Notion with the estimated finish time. Link to same Task if exists.
4. Write entry to `/data/background-tasks.json`.
5. Fill the background window with compatible NAs. Do NOT annotate "machine running in background" — track internally only.
6. User sees: prep slot + normal tasks + finish slot.

**`/data/background-tasks.json` schema:**
```json
[
  {
    "id": "unique-id",
    "type": "laundry | cooking | printing | other",
    "description": "human-readable label",
    "prep_na_id": "notion-page-id",
    "launched_at": "ISO datetime",
    "estimated_finish": "ISO datetime",
    "finish_action": "what to do at finish",
    "finish_na_id": "notion-page-id or null",
    "finish_slotted": true,
    "finish_slot_start": "ISO datetime",
    "finish_slot_end": "ISO datetime"
  }
]
```

### Context-stacking

When selecting and slotting Someday/Maybe items:

- **Always group by context** regardless of `contexts_mode`. If explicit contexts are set in config → use `contexts_field` values. If `auto` → infer from title keywords: "позвонить/call" → @phone, "купить/магазин" → @errands, "компьютер/написать/отправить" → @computer, "дома/дом" → @home.
- **Batch items sharing a context** into the same time slot. Don't interleave @errands and @computer tasks arbitrarily.
- **Trip-based grouping.** If an anchored item implies going out → sweep Someday/Maybe for compatible @errands and bundle them.
- **Parallel slotting.** Multiple short items (<15 min) sharing a context can occupy one slot.
- **If `contexts_mode = "explicit"`**: show context label explicitly in output (e.g. «@errands: купить молоко, зайти на почту»). If `"auto"` → group silently, no explicit label unless it adds clarity.

## Failure modes

- Notion MCP unauthenticated → skip all Notion sections; still send a plan based on Gmail/Calendar if Google is enabled. If neither is available, send «⚠️ Notion недоступен, Google не подключён — план пуст. Запусти `/cgtd-reauth notion`».
- **[Google only]** `invalid_grant` for an account → send Telegram «Google auth для `<email>` истёк. Запусти `/cgtd-reauth google <email>`». **Do NOT exit** — continue with remaining accounts + full Notion plan. Log `degraded` (not `fail`).
- `notion.actions.db_id` empty → skip Notion sections, proceed with Calendar + Gmail digest if available. Do not exit.
