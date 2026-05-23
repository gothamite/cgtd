---
name: feedback-someday-slotting
description: Slot Someday/Maybe NAs into free time blocks with Eisenhower prioritization — do not just list as suggestions
type: feedback
---

During morning ritual, Someday/Maybe NAs must be **actively scheduled** into free slots — not just listed as soft suggestions.

**Rule:** After placing anchors (datetime NAs), fill remaining free blocks with Someday/Maybe items prioritized by Eisenhower matrix (Q1 urgent+important → Q2 important → Q3 urgent → Q4 low). Assign concrete `Date.start` + `Date.end`, write to pending-reviews.jsonl, and ask user to approve before saving to Notion.

**Why:** "Free-slot reserve" means actually scheduling, not suggesting. Listing items without times is not useful.

**How to apply:**
- Applies regardless of rhythm_preset (even in flex mode).
- If rhythm_preset/weekday_blocks not set, default to 09:00–12:00 + 14:00–17:00 blocks.
- Eisenhower classification: urgent+deadline = Q1, important+no deadline = Q2, urgent+unimportant = Q3, low priority = Q4.
- Write the proposed schedule to pending-reviews.jsonl and list in Telegram with numbered items so user can approve/reschedule per item.
