---
name: feedback-google-credentials-in-env
description: Google OAuth credentials are always present in env; google-workspace MCP tools should be tried before declaring no access
metadata:
  type: feedback
---

`GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` are always available in the environment. The `google-workspace` MCP server (configured in `/root/.claude/settings.json`) uses these to manage OAuth tokens stored in `/data/mcp/google-workspace/`.

**Why:** Incorrectly skipping Gmail/Calendar by saying "no Google tokens found" when the credentials were right there.

**How to apply:** In any skill needing Gmail/Calendar, first do `ToolSearch` for google-workspace tools (gmail, calendar, list messages, list events). If tools are available, use them — don't check for raw token files first. If tools are unavailable (cron/MCP-disconnect session), note that specifically rather than saying "no tokens". See also [[feedback_mcp_after_context_overflow]].
