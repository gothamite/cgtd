---
name: feedback-schedule-conflicts
description: Detect and resolve overlapping NA time slots before presenting the daily plan
metadata:
  type: feedback
---

Before presenting anchors in the morning brief (or any scheduling output), scan all datetime NAs for the day and detect overlaps. Never surface a plan with conflicting time slots without flagging and resolving them.

**Why:** Catching conflicts is a core scheduling responsibility — it's the assistant's job, not something to pass back to the user.

**How to apply:**
1. After fetching today's datetime NAs, sort by start time.
2. Walk the list: if any NA's start < previous NA's end → conflict detected.
3. For each conflict: propose moving the lower-priority item to the next free slot (same day if possible, otherwise next available day).
4. Present a conflict-free schedule. If a conflict can't be auto-resolved cleanly, surface it explicitly with options — never silently show overlapping slots as a valid plan.
