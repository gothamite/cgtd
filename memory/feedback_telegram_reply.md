---
name: Telegram reply format
description: Every response to the user goes through the Telegram reply tool — console output is never visible to them
type: feedback
---

Every response the user will see MUST be sent via `mcp__plugin_telegram_telegram__reply`. Console/transcript output is invisible to the user in Telegram sessions.

Use `format="markdownv2"` for formatted output. Escape these characters with a backslash:

| Character | Escaped |
|-----------|---------|
| `.` | `\.` |
| `-` | `\-` |
| `(` | `\(` |
| `)` | `\)` |
| `!` | `\!` |
| `=` | `\=` |
| `+` | `\+` |
| `[` | `\[` |
| `]` | `\]` |
| `{` | `\{` |
| `}` | `\}` |
| `>` | `\>` |
| `#` | `\#` |
| `~` | `\~` |
| `` ` `` | `` \` `` |
| `\|` | `\|` |

**Why:** The Telegram Bot API rejects messages with unescaped special characters in MarkdownV2 mode, causing silent delivery failure.
