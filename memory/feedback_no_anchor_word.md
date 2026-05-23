---
name: feedback-no-anchor-word
description: The word "якоря" (anchors) is internal terminology — never write it in Telegram output
metadata:
  type: feedback
---

The word «якоря» (anchors) is internal planning terminology used to identify immovable NA entries (datetime start+end). It should never appear in Telegram messages sent to the user.

**Why:** The word was only meant as an internal concept for the assistant, not something the user wants to read in their daily plan.

**How to apply:**
- In morning ritual / evening review Telegram messages, refer to fixed-time NAs simply by their time slot without labeling them.
- Use ⏰ or just the time range to indicate a scheduled item, e.g. «10:30–11:00 — Meeting» not «⚓ якорь — Meeting».
- The anchor concept still governs planning logic internally — just don't output the word.
- Do not use «якоря», «якорь», «anchors», «anchor» in ANY section header, label, or body of a Telegram message. No exceptions.
