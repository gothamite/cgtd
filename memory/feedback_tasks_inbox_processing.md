---
name: feedback-tasks-inbox-processing
description: "Tasks with Inbox or Approval-required status need processing; Someday/Maybe checked periodically; assistant proposes time slots"
metadata:
  type: feedback
---

**Rule:** Tasks needing processing = status `status_open` (e.g. "Inbox") OR `status_pending_approval` (e.g. "Approval required"). "Someday/Maybe" tasks are also checked periodically (lower priority, same logic as Someday/Maybe NAs).

**Part A target:** Query Tasks DB for `status = status_open`. Decompose into NAs, set task → `status_pending_approval`. NAs created without datetimes initially.

**Time proposal:** After decomposition (or in morning-ritual/evening-review), the **assistant** proposes specific time slots for each NA based on priority, calendar availability, and Eisenhower matrix. User approves or adjusts — never left blank for user to fill.

**Prioritization:** Priority must be inferred and written to both the Task and its NAs during Part A. Signals:
- Hard deadline ≤7 days or work context → top priority
- Deadline 1–4 weeks → normal
- No deadline / optional → low

**Graduation target:** After all non-deferred NAs get datetimes → task moves to `status_next_to_come` (e.g. "Next to Come"). `status_in_progress` only when the first NA's scheduled time arrives.

**Someday/Maybe tasks:** Their NAs are allowed to also be Someday/Maybe — this is valid, not a missing-datetime violation. Graduation check skips Someday/Maybe NAs.

**Why:** Graduation was going to In Progress instead of Next to Come; time proposals were missing; Someday/Maybe NAs were incorrectly blocking graduation.

**How to apply:**
- In tasks-processing Part A: target `status_open` (whatever that maps to — e.g. "Inbox")
- In graduation check: task goes to `status_next_to_come` on approval; `status_in_progress` only when first NA time arrives
- Always propose times, never leave scheduling to user
- Someday/Maybe NAs on a Someday/Maybe task = OK, don't block graduation

See also: [[feedback_na_requires_datetime]], [[feedback_evening_review_order]], [[feedback_someday_slotting]]
