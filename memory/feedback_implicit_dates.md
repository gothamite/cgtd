---
name: Implicit date parsing
description: Recognize and parse implicit / colloquial deadlines before routing items
type: feedback
---
Many real deadlines aren't ISO dates. Parse them.

Examples (EN/RU/DE):
- "by end of winter" / «до конца зимы» / "Ende des Winters" → last calendar day of the user's winter (Northern hemisphere: Feb 28/29).
- "by start of summer" / «до начала лета» → June 1.
- "EOQ" / "end of quarter" → last day of current quarter.
- "EOM" / "end of month" → last day of current month.
- "next Friday" → resolve relative to today; "this Friday" if before Friday in current week.
- "in 2 weeks" → today + 14 days.
- "before vacation" → user's known vacation dates; if unknown, ask once.

**Why:** if you don't parse these, items end up in Someday/Maybe and get lost. The user wrote a real deadline; treat it as one.

**How to apply:** every time you're about to route something to NA without a Date, scan for implicit-date phrases first. If found, parse to ISO and set Date.
