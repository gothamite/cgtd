---
name: morning-ritual
description: Morning brief — today's anchors, overdue Next Actions, time-blocked plan for the day. Gmail/Calendar included if Google is configured. One Telegram message, awaits user approval.
---

# Morning ritual

Invoked by cron or manually via `/morning`.

## Pre-flight

Read `/data/config.json`. Required: `user.{locale,timezone}`, `notion.next_actions_id`, `schedule.*`, `telegram.chat_id`.

**Google optional:** check `config.google.enabled`. If `false` or `config.google.accounts` is empty → skip all Gmail and Calendar steps silently. Proceed with Notion-only plan.

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

1. **Overdue NA sweep.** Enumerate ALL Next Actions with `Date < today` AND Status indicates "not done" (use `config.gtd.next_actions.status_values.done` and `.cancelled` if set, else use Notion DB defaults). No keyword shortcuts. Dedicated section. Skip if `notion.next_actions_id` is empty.

2. **Today's anchors** (do not move):
   - **[Google only]** Calendar events today across all `config.google.accounts[]`.
   - NA with `Date.start = today`. User already scheduled them.

3. **[Google only] Gmail 24h.** Skip promo/social, only actionable/decision items. Cross-account. Omit this section entirely if `config.google.enabled` is false.

4. **TODAY PLAN with time blocks.** Fill around anchors per `config.schedule.weekday_blocks` (or weekend rule on Sat/Sun). Propose slots with NA tokens for approval. Do NOT re-slot anchored NA. Write approved items via `mcp__notion__notion-update-page` only after user confirms.

5. **Free-slot reserve.** Pull from NA with deferred/someday status AND no Date, prioritized by importance (use `config.gtd.priority_scheme` if set, else Eisenhower Q1→Q4 as default). Apply `config.schedule.weekend_rule` on weekends — `flex` means no category filtering; `rest` means prefer lower-effort items; user's custom narrative overrides all.

6. **Approval required tasks.** If `config.notion.tasks_id` is set and `/data/tasks-pending.json` exists: read it, show task title + NA titles, propose date/time slots. Ask for approval. On approval → PATCH each NA with proposed Date. Remove from `tasks-pending.json`. Skip if tasks not configured.

7. **Flagged tasks.** Read `/data/tasks-flags.json` if it exists. Surface grouped by reason. Skip if file absent.

8. **Closing line** in `config.user.locale`.

## Awaiting user approval

Write a JSON line to `/data/pending-reviews.jsonl`:
```
{"cron_id":"morning-ritual","ts":"<iso>","items":[{"na_id":"...","title":"...","start":"...","end":"..."}]}
```
TTL 6h. When the user replies in Telegram, the inbox-router skill matches against this entry, applies via `notion-update-page`, removes the entry.

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

### Context-stacking for errands

When slotting from deferred/someday items:
- **Location/tool grouping.** Batch NAs that share a context: all-computer tasks together, all outside-errands together. Don't interleave arbitrarily.
- **Scan deferred items.** Always check deferred/someday NAs for items compatible with today's context. Slot the best fits by priority. Don't just list — propose a concrete slot.
- **Parallel slotting.** Multiple errands may share one slot if contextually compatible OR each <15 min.
- **Trip-based grouping.** If an anchored NA implies going out, sweep deferred items for compatible errands.

## Failure modes

- Notion MCP unauthenticated → skip Notion sections, still send a rough plan with what's available.
- **[Google only]** `invalid_grant` for an account → log `fail` with `google_auth_expired:<email>`, ping Telegram to run `/cgtd-reauth`, exit.
- `notion.next_actions_id` empty → skip NA sections, send "⚠️ Next Actions DB not configured" + Gmail/Calendar digest if available.
