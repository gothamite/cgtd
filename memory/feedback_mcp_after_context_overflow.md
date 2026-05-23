---
name: feedback-mcp-after-context-overflow
description: After session context overflows and is summarized, google-workspace MCP becomes unavailable in the continuation session
type: feedback
---

When the Claude Code session context overflows and the conversation is compacted/summarized into a continuation session, the `mcp__google-workspace__*` tools are no longer available (ToolSearch returns no results for them).

**Rule:** After context overflow, do not attempt to use google-workspace MCP tools — fall back to direct API calls immediately. For reauth flows that require the MCP OAuth server, the user must restart the Claude Code session.

**Why:** The MCP server connection is established at session start. When context overflows and a new session is initialized (as a continuation), MCP connections are not re-established — only the Telegram MCP reconnects automatically because it's the channel through which the session is invoked.

**How to apply:**
- If ToolSearch returns no google-workspace tools → session was continued after overflow → direct API only
- For Google reauth: tell user to restart session (docker compose restart + re-run claude command)
- Notion MCP via NOTION_API_KEY env var still works (direct REST) even after overflow
