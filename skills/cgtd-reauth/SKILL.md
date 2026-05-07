---
name: cgtd-reauth
description: Re-run OAuth for Google account(s) or Notion when refresh tokens expire (invalid_grant, scope drift, revoked access). Replaces re-running full /gtd-config.
---

# Re-authorize an external service

Invoked as:
- `/cgtd-reauth google <email>` — single Google account
- `/cgtd-reauth google --all` — every Google account in `config.google.accounts[]`
- `/cgtd-reauth notion` — Notion (update Internal Integration Token)

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

1. Send Telegram:
   > Пришли новый Notion Internal Integration Token (начинается с `secret_...`).
2. Validate: must start with `secret_`. If invalid, ask again.
3. Save to `config.notion.api_key` in `/data/config.json`.
4. Reply:
   > ✓ Токен обновлён. Перезапусти контейнер чтобы применить:
   > ```
   > docker compose restart assistant
   > docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
   > ```
   > После перезапуска Notion MCP подхватит новый токен автоматически.

### Если `/cgtd-reauth notion` не помогает (только с хостовой оболочки)

Если после OAuth Notion MCP всё ещё возвращает ошибку авторизации, сессия MCP может зависнуть. Полный сброс запускается **из терминала на хосте** (не из Telegram):

```bash
docker compose restart assistant
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

После перезапуска отправь `/cgtd-reauth notion` из Telegram ещё раз.

## Auto-detection from skill failures

When a cron skill catches `invalid_grant` / "auth required" / "401" from either MCP:

- Log fail with reason `<service>_auth_expired:<identifier>`.
- Send one Telegram message «<service> auth для <id> истёк. Запусти `/cgtd-reauth <service> <id>`».
- Exit cleanly. No automatic retry.

## Notes

- Refresh tokens issued while a Google OAuth consent screen is in **Testing** status expire after 7 days. Publish to **In production** to avoid weekly re-auth. See `docs/google-setup.md` § "Avoiding the 7-day refresh token expiry."
- Notion tokens are typically long-lived. Common reasons for needing reauth: user revoked access from Notion's "Connections" panel, scope changes, volume corruption.
- Other Google reauth triggers: revoked at myaccount.google.com/permissions, scope drift, volume restore from backup.
