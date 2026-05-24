---
name: feedback-calendar-reschedule-ask-time
description: "When rescheduling a Calendar event that had a specific time, always ask for the new time — never silently set all-day or guess"
metadata:
  type: feedback
---

If a Google Calendar event has a specific datetime and the user asks to reschedule it, always ask for the new time before updating. Never silently convert it to all-day or pick a time unilaterally.

**Why:** Moving a timed Calendar event to another day as all-day leaves an incomplete/ambiguous calendar entry. The user needs to know the new time to plan their day.

**How to apply:** When moving a timed Calendar event to a different day, ask: «На какое время поставить [событие] на [дата]?» before patching the Calendar API.
