---
name: feedback-implicit-approval
description: "Positive responses after a proposed plan = implicit approval; always resolve pending actions, don't drop them silently"
metadata:
  type: feedback
---

Positive responses like "Отлично", "Хорошо", "Ок", "Супер", "Perfect", "Great" after a proposed plan = implicit approval. Do not wait for a literal "да применяй".

**Why:** User said "Отлично" after the day plan, then had to ask "В Notion обновила?" because the assistant sent only a sticker and dropped the thread. This loses context of a pending action.

**How to apply:**
- Always track open pending actions within a conversation (e.g., "applying to Notion awaiting confirmation").
- When user says something positive, check if there's a pending action and execute it or explicitly ask about it — don't let it silently disappear.
- A sticker/emoji-only reply is only appropriate when there is genuinely nothing left to do. If there's a pending action, resolve it first.
