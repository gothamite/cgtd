---
name: Contextual deadline inference
description: Don't default to Someday/Maybe — reason from date, season, weather, use-case, and Notion events to infer a sensible Date
type: feedback
---

## Status–Date invariant

- **Not started** → MUST have a Date. If a date cannot be inferred, route to Inbox with «дата не найдена — уточнить», not to Someday/Maybe.
- **Someday/Maybe** → the ONLY status that may have no Date.

**Why:** Someday/Maybe is a graveyard. Items there rarely get done. Most "undated" items actually have an implied deadline once you reason from context.

## Heuristics

When an item lacks an explicit deadline, apply these in order before defaulting to Someday/Maybe:

- **Daily-use repair / replacement** (broken tool, worn shoes, dead charger) → 1–2 weeks. User wants this fixed soon.
- **Seasonal clothing / gear** (winter coat in October, swimsuit in May) → 3–4 weeks before peak season.
- **Health / admin** (annual checkup, tax filing) → 2 weeks unless externally pinned.
- **Gifts** → recipient's event date − buffer (1 week for shipping, 2 weeks for handmade).
- **Package / storage pickup** → email date + stated pickup window − 1 day (pick up the day before the deadline).
- **Marketplace reply** (Kleinanzeigen, eBay Kleinanzeigen, similar) → respond within 1–2 days.
- **Pure want / aspirational** ("learn Italian", "read War and Peace") → Someday/Maybe with no Date.

## Cross-Notion event lookup

If the action is tied to a named event (concert, trip, ceremony, course), search NA + Tasks by event title before assigning a date.

**Lead time by domain:**

| Domain | Lead time |
|--------|-----------|
| Transport tickets (concert, flight, train) | book 1–2 months before event |
| Accommodation (hotel, Airbnb) | book 2–3 months before event |
| Gift | prepare 1–2 weeks before event |
| Outfit / costume | prepare 1 week before event |

Algorithm:
1. Extract event name from the item text.
2. `mcp__notion__search` the event name across NA + Tasks databases.
3. If a matching event page with a Date is found → compute `event_date − lead_time` as the action date.
4. If no match → fall back to other heuristics or Inbox.

**How to apply:** before routing to Someday/Maybe, run through all heuristics and the cross-Notion lookup. If any fits, set a real Date and route to Next Actions instead. If genuinely aspirational with no derivable date, Someday is correct.
