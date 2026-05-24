---
name: tasks-processing
description: Daily tasks processor — decomposes Inbox tasks into NAs with priority, checks active tasks for issues, flags tasks needing attention. Runs after process-inbox.
---

# Tasks Processing

Invoked by cron (default `45 21 * * *`) or manually via `/tasks-processing`.

## Pre-flight

Read `/data/config.json`. Required: `notion.{tasks_id,next_actions_id}`, `telegram.chat_id`.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start tasks-processing)
/app/bin/cron-log.sh lock tasks-processing || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

## Dependency check

Before proceeding, verify process-inbox ran today:
```
/app/bin/cron-log.sh last-ok process-inbox
```
If result is empty or timestamp is before today's date in `config.user.timezone` → log `ok "$RID"` and exit silently.

## Procedure

### Part A — Decompose Inbox tasks

1. Query Tasks DB for Status = "Inbox" via `mcp__notion__notion-query-database-view` with filter `Status = Inbox`.
2. Skip tasks that already have Status = "Approval required" (already processed).
3. For each Inbox task:

   **a. Read task data**: Name, body/description, Sub-task relation, Due, Priority, `?Type`, P&P tags.

   **b. Infer Priority** if not set — use these signals:
   - Hard deadline within 7 days, or task tagged work/professional → `high`
   - Clear deadline 1–4 weeks out, or moderate work context → `normal`
   - Optional, personal, low-stakes, or no deadline → `low`
   Write inferred value to Task's Priority field via `mcp__notion__notion-update-page`.

   **c. Decompose into atomic NAs**: break task into concrete verb-object actions.
   Rules (same as regular NAs):
   - Each NA completable in one sitting (≤2h)
   - Start with a strong verb (написать, позвонить, купить, проверить, отправить…)
   - No Date/time — scheduling happens after user approval
   - Status: `Not started`
   - Priority: inherit from task (use the inferred value from step b)
   - For decomposition patterns («X + Y», lists, «разобраться с...», research→action chains), apply `/data/memory/feedback_task_vs_na.md`.

   **Minimum NAs rule:** If decomposition yields only 1 NA → the Task wrapper is unnecessary. Create that NA as standalone (no Task relation), set the Task Status → `Done` (or delete via Notion REST API). Do not leave a Task with a single linked NA.

   **d. Create each NA** via `mcp__notion__notion-create-pages` in `config.notion.next_actions_id`:
   - `Name`: NA title
   - `Status`: Not started
   - `Priority`: inherited
   - `Task`: relation → this task's page_id

   **e. After all NAs created** → update Task Status to `Approval required`.

4. Collect created tasks: list of `{task_id, task_title, task_priority, task_due, proposed_nas[{na_id, title, priority}]}`.

### Part B — Check active tasks

**Step 1 — Graduation from "Approval required".**

Query Tasks DB for Status = "Approval required". For each such task:
1. Fetch all linked NAs from the `Next Actions` relation field.
2. Check: does every linked NA satisfy both conditions?
   - `Date` field is set AND the value is a datetime (not date-only) → `is_datetime = true`
   - Status ≠ "Someday/Maybe"
3. If ALL NAs satisfy both conditions → task is approved. Compute new status:
   - Due date < today OR Due ≤ today + 3 days → "Not Started"
   - Due ≤ today + 14 days → "Next to Come"
   - No Due OR Due > today + 14 days → "Maybe"
   PATCH task Status to computed value. Remove task from `/data/tasks-pending.json`.
4. If ANY NA lacks a datetime or is Someday/Maybe → leave task in "Approval required". Leave it in `tasks-pending.json`.

5. Query Tasks DB for Status in ["Not Started", "Next to Come", "Maybe", "In Progress", "Waiting"].
6. For each task, resolve linked NAs from the `Next Actions` relation field.
7. Flag task if ANY condition is met:
   - **no_nas**: Status is "Not Started" or "In Progress" AND no linked NAs AND task created > 3 days ago
   - **all_nas_done**: All linked NAs are Done/Cancelled but Task status ∉ {Done, Canceled, Archive}
   - **deadline_no_schedule**: `Due` date within 3 days AND no linked NA has a future `Date`
   - **stale**: Status "In Progress" AND no linked NA was modified in the last 7 days
8. Remove flags for tasks that no longer match any condition.

### Save state

**`/data/tasks-pending.json`** — tasks awaiting user approval:
```json
{
  "created_at": "<iso>",
  "ttl_hours": 36,
  "tasks": [
    {
      "task_id": "page_id",
      "task_title": "...",
      "task_priority": "high|normal|low",
      "task_due": "YYYY-MM-DD or null",
      "proposed_nas": [
        {"na_id": "page_id", "title": "...", "priority": "high|normal|low"}
      ]
    }
  ]
}
```
If file already exists and is within TTL, merge new tasks in (don't overwrite unresolved approvals).

**`/data/tasks-flags.json`** — tasks needing attention:
```json
{
  "last_run": "<iso>",
  "flagged": [
    {
      "task_id": "page_id",
      "task_title": "...",
      "task_url": "https://notion.so/...",
      "reason": "no_nas|all_nas_done|deadline_no_schedule|stale",
      "flagged_at": "<iso>"
    }
  ]
}
```
Overwrite on each run (flags are recomputed fresh each time).

### Output (one Telegram message)

```
⚙️ Tasks: A разобрано → Approval required, B отмечено → требуют внимания
```
Silent if nothing to process and no new flags.

## Idempotency

- Tasks already in "Approval required" status are skipped in Part A.
- Part B flags are recomputed fresh each run — safe to retry.

## Failure modes

- Notion MCP unauthenticated → log `ok`, exit silently (same as process-inbox).
- Partial failure: NA creation + status update are paired. On retry, already-updated tasks (Approval required) are skipped.
