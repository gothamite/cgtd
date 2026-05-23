---
name: feedback-reminders-as-na
description: "When user asks for a reminder, create Google Calendar event with popup reminder; NA in Notion is a duplicate/reference"
metadata:
  type: feedback
---

When the user asks to be reminded about something at a specific time:

1. **Primary:** Create a Google Calendar event at the reminder time with `reminders.overrides: [{method: "popup", minutes: 0}]`. This fires a native phone notification reliably regardless of session state.
2. **Secondary:** Create a Notion Next Action with the same date/time — serves as a duplicate/reference visible in morning ritual and evening review.
3. Cron job is NOT needed — Calendar handles the actual notification.

**Why:** Cron reminders are session-only and die on restart. Notion API doesn't support reminders. Google Calendar popup notifications work natively on the user's phone.

**How to apply:** Always do both (GCal event + Notion NA) when user says "напомни" or "remind me". Default popup at minutes=0 (at event time).
