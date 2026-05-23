---
name: feedback-cron-no-mcp
description: Remote agent sessions fired by cron don't have google-workspace or notion MCP tools loaded
type: feedback
---

Cron-fired remote agent sessions do NOT have `mcp__google-workspace__*` or `mcp__notion__*` tools available. Any skill that calls these tools will fail with "tool not available" or similar.

**Why:** Claude Code remote agents start without MCP server connections. Only the main interactive session has MCP tools loaded.

**How to apply:** When running in a cron/skill context and MCP tools are unavailable:
- Google API: load credentials from `/root/.google_workspace_mcp/credentials/<email>.json` and use `googleapiclient.discovery.build()` directly
- Notion API: use REST directly with `NOTION_API_KEY` env var and `https://api.notion.com/v1/`
- Check tool availability by attempting ToolSearch — if google-workspace tools don't appear in deferred list, fall back to direct APIs immediately rather than trying to call them
