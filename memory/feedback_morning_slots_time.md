---
name: feedback-morning-slots-time
description: Always check current local time before proposing NA slots; never propose slots in the past
metadata:
  type: feedback
---

Never propose time slots that have already passed in the user's local timezone (`config.user.timezone`).

**Why:** Morning brief proposing slots that have already passed looks careless and creates a useless plan.

**How to apply:** Before building the slot plan in morning-ritual (or any NA slotting), run `TZ=$(jq -r .user.timezone /data/config.json) date` to get current local time. Only propose slots that start at or after "now + ~15 min buffer". Find the next available free gap in the anchor schedule from that point forward.
