---
name: feedback-notion-reauth
description: How to fix Notion MCP 401 errors; what works and what doesn't
type: feedback
---

The "claude.ai Notion" MCP (`mcp__claude_ai_Notion__`) uses `https://mcp.notion.com/mcp`. Its OAuth credential is stored in `/data/claude-home/.credentials.json` under key `notion_mcp`.

**When 401 errors appear:**
- The `notion_mcp` credential expired or was revoked
- `/mcp` "Reconnect" does NOT re-trigger OAuth — it only reconnects the HTTP transport
- Dynamic client registration at `mcp.notion.com/register` is 403 (closed system)

**What fixes it:**
1. Remove "claude.ai Notion" from `claudeAiMcpEverConnected` in `/root/.claude.json`
2. User runs `/mcp` in Claude Code terminal — this time shows Connect (OAuth) rather than Reconnect
3. After OAuth completes, `notion_mcp` credential reappears in `.credentials.json`

**What does NOT work:**
- `claude mcp remove notion` — server is named "claude.ai Notion", not "notion"; CLI can't remove it
- Deleting `notion_mcp` from credentials manually — doesn't trigger re-auth on its own
- Running `claude mcp list` or `claude mcp get` from within a skill — disconnects the Telegram MCP tools from the session (don't do this)

**Why:** This is a claude.ai-managed integration; auth is through Claude.ai's OAuth proxy, not a standard user-managed flow.
