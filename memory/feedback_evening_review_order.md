---
name: feedback-evening-review-order
description: process-inbox and tasks-processing must both complete before evening-review
metadata:
  type: feedback
---

Evening review fires at 21:30 (default). Both process-inbox and tasks-processing must have run today before evening-review starts.

**Why:** The evening review surfaces task approvals and flags from tasks-processing output. Running it without completed inbox/tasks processing means incomplete data.

**How to apply:**
- Cron order: process-inbox → tasks-processing → evening-review
- On catch-up at session start: run in that order — never skip tasks-processing before evening-review
- tasks-processing itself also checks if process-inbox ran today before proceeding
