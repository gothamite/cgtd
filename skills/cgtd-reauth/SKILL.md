---
name: cgtd-reauth
description: Re-run OAuth for Google account(s) or Notion when refresh tokens expire (invalid_grant, scope drift, revoked access). Replaces re-running full /gtd-config.
---

# Re-authorize an external service

Invoked as:
- `/cgtd-reauth google <email>` — single Google account
- `/cgtd-reauth google --all` — every Google account in `config.google.accounts[]`
- `/cgtd-reauth notion` — Notion (hosted OAuth MCP)

Runs over Telegram or terminal — both work. The user opens the OAuth link on the same machine running Docker (Telegram Desktop recommended for the Telegram path).

## Pre-flight

- Read `/data/config.json`. Abort if `init_complete: false` («запусти `/gtd-config` сначала»).
- If port `8000` isn't reachable from the user's browser (remote VPS without SSH tunnel), print the SSH local-forward command and wait.

## Procedure — Google

For each target email:

1. Delete `/data/mcp/google-workspace/<email>.json` (cached token). The next API call will trigger a fresh OAuth flow.
2. Call `mcp__google-workspace__list_calendars user_google_email=<email>` — server returns an authorization URL.
3. Send URL via Telegram (or print to terminal). User opens on the Docker host machine, completes consent.
4. Wait for «done». Retry `list_calendars`. On success → next account.
5. Final reply: «✓ <email> reauthorized — cron jobs resume on next firing.»

## Procedure — Notion

1. Clear Notion's cached OAuth token from `/data/claude-home/` (location depends on Claude Code's MCP token storage; if uncertain, advise the user to remove the `notion` MCP via `claude mcp remove notion` and re-add it via the settings.json template — the next call triggers fresh OAuth).
2. Call `mcp__notion__notion-search` with empty query — returns OAuth URL.
3. Send URL. User opens on Docker host, signs in, **re-picks pages to share**.
4. Wait for «done». Retry. On success → reply «✓ Notion reauthorized».

## Auto-detection from skill failures

When a cron skill catches `invalid_grant` / "auth required" / "401" from either MCP:

- Log fail with reason `<service>_auth_expired:<identifier>`.
- Send one Telegram message «<service> auth для <id> истёк. Запусти `/cgtd-reauth <service> <id>`».
- Exit cleanly. No automatic retry.

## Notes

- Refresh tokens issued while a Google OAuth consent screen is in **Testing** status expire after 7 days. Publish to **In production** to avoid weekly re-auth. See `docs/google-setup.md` § "Avoiding the 7-day refresh token expiry."
- Notion tokens are typically long-lived. Common reasons for needing reauth: user revoked access from Notion's "Connections" panel, scope changes, volume corruption.
- Other Google reauth triggers: revoked at myaccount.google.com/permissions, scope drift, volume restore from backup.
