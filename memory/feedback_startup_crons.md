---
name: feedback-startup-crons
description: Session startup (CronList + recreate missing crons) must be done before processing any Telegram message
type: feedback
---

Always complete the full session startup procedure BEFORE handling any incoming Telegram message or request:
1. Read `/data/config.json`
2. Call `CronList`
3. Recreate any missing cron jobs

**Why:** In a session where a Telegram message arrived immediately, the startup was skipped and crons were never recreated. The user had to manually ask why crons were missing.

**How to apply:** Treat session startup as a blocking pre-step. Even if a Telegram message is waiting, run the startup check first — it's silent and fast.
