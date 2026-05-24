---
name: tasks-processing
description: Daily tasks processor — decomposes Inbox tasks into NAs with priority, checks active tasks for issues, flags tasks needing attention. Runs after process-inbox.
---

# Tasks Processing

Invoked by cron (default `45 21 * * *`) or manually via `/tasks-processing`.

## Pre-flight

Read `/data/config.json`.

**Projects source.** Resolve which DB contains multi-step goals:

```
projects_id     = notion.projects.db_id (resolved from same_as_* chain)
projects_name   = notion.projects.db_name
projects_filter = {property: projects.filter_property, value: projects.filter_value} or null
actions_id      = notion.actions.db_id (resolved) → fallback: notion.capture.db_id
actions_name    = notion.actions.db_name
```

If `projects_id` is empty → log `ok "$RID"` with `projects_not_configured`, exit silently. This skill is a no-op when no projects layer exists.

**Status values.** Read from `notion.projects.fields.*`:
- `status_field` → the property name for status; if null → skip all status-based routing
- `status_open` → "new / не начато" state; fallback `"Not Started"`
- `status_pending_approval` → awaiting scheduling; fallback `"Approval required"` (may be absent)
- `status_in_progress` → fallback `"In Progress"`
- `status_next_to_come` → post-approval pre-active state (e.g. "Next to Come"); if absent, fall back to `status_in_progress` for graduation
- `status_done` → fallback `"Done"`
- `status_cancelled` → fallback `"Cancelled"`

**Actions relation.** `notion.projects.fields.actions_relation` → the property name on the projects DB that links to the actions DB. If null → graduation logic (Part B Step 1) is skipped entirely; surface projects as-is without linked-action checks.

**Filter.** Apply `projects_filter` to every query that fetches projects — this allows non-standard setups (e.g. tag = "project" in a shared DB) to work transparently.

## Logging wrapper

```
RID=$(/app/bin/cron-log.sh start tasks-processing)
/app/bin/cron-log.sh lock tasks-processing || exit 0
```
End with `ok "$RID"` or `fail "$RID" "msg"`.

If `config.gtd.unmappable_warning: true` → surface all projects DB items as-is; skip Status-based routing; label Telegram output «⚠️ схема проектов не распознана — показываю всё».

## Dependency check

Before proceeding, verify process-inbox ran today:
```
/app/bin/cron-log.sh last-ok process-inbox
```
If result is empty or timestamp is before today's date in `config.user.timezone` → log `ok "$RID"` and exit silently.

All queries below must include `projects_filter` if set (e.g. add a filter clause `{property: projects_filter.property, select: {equals: projects_filter.value}}`). This applies to every `API-query-data-source` call in Part A and Part B.

**`API-query-data-source` note:** The `data_source_id` parameter is the database UUID (same value as `projects_id` / `actions_id` from config). Pass the DB UUID directly as `data_source_id`. If the call fails with a 404/invalid ID error, call `mcp__notion__API-retrieve-a-database` first to get the correct `data_source_id` from the response.

## Procedure

### Part A — Decompose new projects

1. Query `projects_id` for items with `status_field = status_open` (or an "inbox/new" equivalent if `status_pending_approval` is absent — use the first non-done, non-in-progress status value as the "new" state). Apply `projects_filter` if set.
2. Skip items that already have `status_field = status_pending_approval` (already processed). If `status_pending_approval` is not defined in config → skip items that have any linked action in `actions_relation` field.
3. For each new project item:

   **a. Read data**: Name, body/description, linked actions (via `actions_relation` field if set), due date (via `projects_fields.due` if set), priority (via `projects_fields.priority` if set).

   **b. Infer Priority** if `projects_fields.priority` is set but empty — signals:
   - Hard deadline within 7 days, or work/professional context → top priority value
   - Clear deadline 1–4 weeks out → mid priority value
   - Optional / low-stakes / no deadline → low priority value
   Write inferred value via `mcp__notion__API-patch-page`.

   **c. Decompose into atomic actions**: break into concrete verb-object steps.
   Rules:
   - Each action completable in one sitting (≤2h)
   - Start with a strong verb
   - No date/time yet — scheduling happens after user approval
   - Status: `actions_fields.status_open`
   - Priority: inherit from project
   - Apply `/data/memory/feedback_task_vs_na.md` for decomposition patterns.

   **Minimum actions rule:** If decomposition yields only 1 action → the project wrapper is unnecessary. Create that action standalone (no project relation), set project status → `status_done`. Do not leave a project with a single linked action.

   **d. Create each action** via `mcp__notion__API-post-page` in `actions_id`:
   - `Name`: action title
   - `status_field`: `status_open` (if field exists)
   - `priority_field`: inherited (if field exists)
   - `actions_relation` field on the project → link back (if `actions_relation` is set)

   If `actions_id == projects_id`: create as a sub-item or tagged entry in the same DB rather than a separate page.

   **e. After all actions created** → update project status to `status_pending_approval` (if defined). If not defined → add a "pending" tag or leave as-is; record in `tasks-pending.json` anyway.

4. Collect: list of `{project_id, project_title, priority, due, proposed_actions[{action_id, title, priority}]}`.

### Part B — Check active projects

**Step 1 — Graduation from pending approval.** (Skip entirely if `actions_relation` is null or `status_pending_approval` is not defined.)

Query `projects_id` for items with `status_field = status_pending_approval`. Apply `projects_filter`. For each:
1. Fetch all linked actions via `actions_relation` field.
2. Check: does every linked action satisfy both conditions?
   - `date_field` is set AND value is a datetime (not date-only)
   - Status ≠ `status_deferred`
3. If ALL non-deferred linked actions have a datetime (date + time) set → project is approved:
   - PATCH project status to `status_next_to_come` if defined in config, else `status_in_progress`.
   - Remove from `/data/tasks-pending.json`.

   **Someday/Maybe NAs do NOT block graduation.** Actions with status = `status_deferred` are intentionally undated — skip them entirely in this check. Only non-deferred NAs without datetimes block graduation.

4. If ANY non-deferred linked action lacks a datetime → leave project in pending. Leave in `tasks-pending.json`.

5. Query `projects_id` for items with status ∉ {`status_done`, `status_cancelled`, `status_deferred`}. Apply `projects_filter`.
6. For each, resolve linked actions (if `actions_relation` is set).
7. Flag project if ANY condition is met:
   - **no_actions**: status = `status_open` or `status_in_progress` AND no linked actions AND project created > 3 days ago. (Skip if `actions_relation` is null.)
   - **all_actions_done**: all linked actions are done/cancelled but project status ∉ {done, cancelled}. (Skip if `actions_relation` is null.)
   - **deadline_no_schedule**: `due` date within 3 days AND no linked action has a future `date_field`. (Skip if `due` or `actions_relation` is null.)
   - **stale**: `status_in_progress` AND no linked action was modified in the last 7 days. (Skip if `actions_relation` is null.)
8. Remove flags for projects that no longer match any condition.

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
⚙️ <projects_name>: A разобрано → ожидают планирования, B отмечено → требуют внимания
```
Use `projects_name` as the label. Silent if nothing to process and no new flags.

## Idempotency

- Tasks already in "Approval required" status are skipped in Part A.
- Part B flags are recomputed fresh each run — safe to retry.

## Failure modes

- Notion MCP unauthenticated → log `ok`, exit silently.
- Partial failure: action creation + status update are paired. On retry, already-updated projects (pending approval status, or with linked actions) are skipped.
