---
name: cgtd-reauth
description: Re-run Google OAuth for one or all configured accounts when refresh tokens expire (invalid_grant, scope drift, revoked access). Replacement for re-running full /init-cgtd.
---

# Re-auth a Google account

Invoked as `/cgtd-reauth <email>` or `/cgtd-reauth --all`. Triggers OAuth flow for the named account(s) without touching the rest of the config.

## Pre-flight

- Read `/data/config.json`. Abort if `google.accounts[]` is empty («nothing to re-auth — run /init-cgtd first»).
- If port `8000` is not reachable from the host browser (remote VPS), print SSH local-forward command and wait for user confirmation.

## Procedure

For each target email (single arg, or all of `config.google.accounts`):

1. Delete the cached token at `/data/mcp/google-workspace/<email>.json` (workspace-mcp will trigger a fresh OAuth flow on next call).
2. Call `mcp__google-workspace__list_calendars user_google_email=<email>`. Print the returned authorization URL.
3. Wait for the user to confirm in terminal that they completed the browser flow. Retry the `list_calendars` call. On success → move to next.
4. On final success, print: «✓ <email> re-authorized. Cron jobs will resume on next firing.»

## Auto-detection from cron failures

When a cron skill (proactive-inbox, morning-ritual, evening-review) catches an `invalid_grant` or "auth required" error from the google-workspace MCP, it should:

- Log fail with reason `google_auth_expired:<email>`.
- Send one Telegram message «Google auth для <email> истёк. Запусти `/cgtd-reauth <email>` через `docker compose exec gtd claude`.»
- Exit cleanly (do NOT loop or retry).

The user runs the command at their convenience. No automatic retry.

## Notes

- Refresh tokens issued while the OAuth consent screen is in **Testing** status expire after 7 days. Publish the consent screen to **In production** to avoid weekly re-auth. See `docs/google-setup.md` § "Avoiding the 7-day refresh token expiry."
- Other reasons re-auth is needed: user revoked access at myaccount.google.com/permissions, scope drift, volume corruption.
