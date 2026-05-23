---
name: feedback-notion-token-location
description: Where to find the working Notion token — check env before asking the user
type: feedback
---

The Notion Internal Integration Token is available as the `NOTION_API_KEY` environment variable. Use it directly with the Notion REST API (`https://api.notion.com/v1/`).

**Why:** `/data/mcp/notion/tokens.json` may contain an OAuth token that is stale/invalid. The env var is always the authoritative source.

**How to apply:** Before asking the user for a Notion token or triggering reauth, check `os.environ.get('NOTION_API_KEY')` or `$NOTION_API_KEY` in shell. If present and non-empty, use it — no reauth needed.
