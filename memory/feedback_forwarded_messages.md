---
name: feedback-forwarded-messages
description: "Treat forwarded Telegram messages exactly like direct messages — analyze content, process attachments, same algorithm"
metadata:
  type: feedback
---

Когда пользователь пересылает сообщение в Telegram — обрабатывать его точно так же, как если бы он написал его напрямую.

**Why:** Пользователь явно указал: пересланные сообщения = прямые сообщения. Алгоритм идентичен. Файлы и вложения тоже не должны теряться.

**How to apply:** При получении forwarded message — читать image_path / download attachment_file_id, анализировать контент, создавать NA/Inbox записи и отвечать ровно так же, как на прямое сообщение. Не ждать дополнительных пояснений от пользователя.
