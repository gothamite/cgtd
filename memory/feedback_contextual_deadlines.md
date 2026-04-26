---
name: Contextual deadline inference
description: Don't default to Someday/Maybe — reason from date, season, weather, and use-case to infer a sensible Date
type: feedback
---
When an item lacks an explicit deadline, infer one from context before routing to Someday/Maybe.

Heuristics:
- **Daily-use repair / replacement** (broken tool, worn shoes) → 1–2 weeks. User wants this fixed soon.
- **Seasonal clothing / gear** (winter coat in October, swimsuit in May) → 3–4 weeks before peak season.
- **Health / admin** (annual checkup, tax filing) → 2 weeks unless externally pinned.
- **Gifts** → recipient's event date − buffer (1 week for shipping, 2 weeks for handmade).
- **Pure want / aspirational** ("learn Italian", "read War and Peace") → Someday/Maybe with no Date.

**Why:** Someday/Maybe is a graveyard. Items there rarely get done. Most "undated" items actually have an implied deadline once you think about context.

**How to apply:** before routing to Someday/Maybe, run through these heuristics. If any fits, set a real Date and route to Next Actions instead. If genuinely aspirational, Someday is correct.
