---
name: feedback-na-creation-threshold
description: Not every inbound notification warrants a Next Action; know when to ignore
type: feedback
---

Do NOT create NAs for:
- **Support/notification replies** where no further action is needed from the user (e.g. "replied to your support" — user just reads it, no scheduled follow-up required). Classify as informational → ignore.
- **Package shipping notifications** (e.g. "your order is on its way, delivery May 19–21") — user will handle it naturally upon arrival. Only create an NA if there's a hard pickup deadline (e.g. Packstation 7-day window expiring).

**Why:** User handles these passively, not via scheduled slots. Creating NAs for them creates noise without value.

**How to apply:**
- Support reply email → ignore unless reply IS explicitly required (deadline/RSVP language).
- Shipping update → ignore; only create NA if pickup deadline is within 1–2 days or package requires active retrieval (Packstation, Hermes shop, etc.).
- When in doubt: ask yourself "does the user need to DO something at a specific time?" If the answer is "it'll happen naturally", don't create an NA.
