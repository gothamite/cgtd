---
name: feedback-na-time-blocks
description: NA database is the user's daily calendar; entries with fixed start+end are anchors that cannot be re-slotted
type: feedback
---

Next Actions is not just a task list — it is a **time-blocked daily calendar**. Every NA entry is a scheduled slot in the user's day.

**Rule:** An NA is an **anchor** only when `Date.start` is a **datetime** (has a time component, not date-only) AND `Date.end` is set. Date-only NAs are flexible regardless of which day they fall on. The daily agenda is always built *around* anchors.

**Why:** The user explicitly schedules anchors (events, appointments, fixed commitments). Suggesting to move them would be incorrect and disruptive.

**How to apply:**
- When proposing a day plan (morning ritual, manual requests), first enumerate all anchors (NA with datetime Date.start today), then fill remaining free slots with non-anchored NAs and Someday items.
- When creating a new NA with a time, check for anchor conflicts before assigning the slot.
- Date-only NAs (no time component) are flexible — they can be slotted into any free block.
- Always use `Date.start` + `Date.end` when time is known; `Date` alone only when no time is available.
- **During process-inbox:** when routing an NA to a specific date, check the calendar for that day and assign a concrete `Date.start` + `Date.end` time slot — don't leave it as date-only. Look at existing anchors first, then fill free windows.
