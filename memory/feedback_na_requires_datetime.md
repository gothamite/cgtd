---
name: feedback-na-requires-datetime
description: NA must have a specific date+time unless Someday/Maybe; task only graduates from Approval required when all NAs have datetimes
metadata:
  type: feedback
---

**NA rule:** Every NA must have a specific date AND time set, unless its status is "Someday/Maybe". An NA without a datetime (or with only a date but no time) and status ≠ Someday/Maybe is in a "pending scheduling" state — not ready, not active.

**Task approval rule:** A task stays in "Approval required" until ALL its linked NAs have a datetime Date set (`is_datetime = true`) and none are Someday/Maybe. Only then is the task considered approved and its status updated to Not Started / Next to Come / Maybe based on deadline proximity.

**Why:** Tasks were getting stuck in "Approval required" forever because the skill never checked whether NAs had received dates. The graduation logic was missing entirely.

**How to apply:**
- In tasks-processing Part B step 1: for each "Approval required" task, check all linked NAs for datetime completeness. If all approved → compute new status and PATCH.
- In morning-ritual and evening-review: when surfacing pending NAs for scheduling, always highlight NAs that lack a datetime as "needs date+time" — not just "needs approval".
- Never count an NA as "open/active" if it has no datetime and is not Someday/Maybe.
