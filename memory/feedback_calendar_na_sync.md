---
name: feedback-calendar-na-sync
description: Always sync Google Calendar events with matching Notion NAs — same event must have identical time in both sources
metadata:
  type: feedback
---

When planning or rescheduling, always check if a Notion NA also exists as a Google Calendar event. If it does, both must be updated — never update one source without the other.

**Why:** A task rescheduled in Notion NA but not in Google Calendar creates two sources of truth, causing confusion and missed appointments.

**How to apply:**
1. When fetching NAs for the day, cross-reference with Google Calendar events by title similarity and time overlap.
2. If an NA and a Calendar event match (same title/topic, same day), treat them as the same event — keep times in sync.
3. When rescheduling an NA that has a matching Calendar event → also PATCH the Calendar event via the API.
4. When rescheduling a Calendar event → also update the linked NA in Notion.
5. Always verify sync after any rescheduling operation.
