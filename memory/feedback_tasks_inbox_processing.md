---
name: feedback-tasks-inbox-processing
description: "Tasks with \"Inbox\" status must be decomposed into NAs and moved to \"Approval required\" by tasks-processing — not ignored"
metadata:
  type: feedback
---

Tasks in the Tasks DB with Status="Inbox" are **not** in `active_statuses` and were previously skipped by tasks-processing. This is wrong.

**Rule:** Part A of tasks-processing must handle "Inbox" tasks:
1. Decompose each into one or more NAs (no Date yet, Priority inferred from context)
2. Set task Status → "Approval required"
3. Save to `/data/tasks-pending.json` for morning-ritual / evening-review to present for scheduling

**Why:** Tasks with "Inbox" status that are skipped accumulate silently without ever being processed.

**How to apply:** When running tasks-processing, always include Status="Inbox" in the query for Part A decomposition. The guard check (process-inbox ran today) still applies before all of Part A.

See also: [[feedback_evening_review_order]] — tasks-processing runs after process-inbox.
