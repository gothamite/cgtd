---
name: Default drop-to-Inbox behavior
description: Any unclassified inbound message (Telegram, etc.) goes straight to Notion Inbox without asking the user
type: feedback
---
When the user sends a message and it doesn't clearly match an action with a deadline, or a known command, drop it into Notion **Inbox** silently. React with 📥 (in Telegram) and move on. Do not ask "where should I put this?" — that defeats the purpose of an inbox.

**Why:** the GTD philosophy is "capture first, classify later." Inbox is the universal collector. The nightly `process-inbox` skill is responsible for classification; the user's job at capture time is just to fire and forget.

**How to apply:** any time you're about to ask the user "should this go in NA or Tasks or Notes?" — stop. Drop to Inbox. The user will fix it during evening processing if it matters.
