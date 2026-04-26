---
name: init-cgtd
description: Terminal-side bootstrap. Brings up Docker, installs the Telegram channel plugin, configures the bot, pairs the user, and hands off to the Telegram-driven interview for everything else. Run this once from the terminal; never re-run after the first success — use the menu in /gtd-config (over Telegram) instead.
---

# Bootstrap (terminal)

Invoked manually as `/init-cgtd` inside `docker compose exec assistant claude`. This skill **only** does the minimum needed to start a Telegram conversation. Everything else — locale, name, timezone, Google OAuth, Notion OAuth, Drive folder, GTD interview, schedule, crons — happens during the Telegram conversation that follows (skill: `gtd-interview`).

## Why split this way

The Telegram channel plugin is itself an MCP and must be installed and paired before any Telegram conversation can happen. So Phase 1 (terminal) sets up Telegram; Phase 2 (Telegram) sets up everything else. This matches the project's pitch: a personal AI assistant you talk to in Telegram.

## Pre-flight

1. Read `/data/install_id` (entrypoint seeded it). Treat as immutable.
2. If `/data/config.json` already exists with `init_complete: true` → print «✓ already bootstrapped — message your bot in Telegram and ask `/gtd-config` to reconfigure» and exit. This skill is one-shot.
3. Read env vars: `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`. Warn (don't abort) if missing — Google can be re-set during the interview after they edit `.env`.

## Procedure

Walk the user through, in order:

### 1. Install the Telegram channel plugin

Print:
> First, find your Claude Code marketplace and install the Telegram channel:
> ```
> /plugin marketplace list
> /plugin install telegram@<marketplace>
> ```
> When done, type `/plugin list` and tell me the exact spec line for the Telegram plugin (e.g. `plugin:telegram@anthropic`).

Wait for the user to confirm. If their spec differs from the default `plugin:telegram@anthropic`, instruct them to set `CGTD_CHANNEL_SPEC=<their-spec>` in `.env`.

### 2. Configure the bot token

Print:
> Now configure your bot. You should already have a token from BotFather (see `docs/telegram-setup.md` if not):
> ```
> /telegram:configure
> ```
> Paste the token when asked.

Wait for confirmation.

### 3. Pair your Telegram account

Print:
> ```
> /telegram:access
> ```
> Then DM your bot any message. The bot replies with a pairing code; approve it via `/telegram:access` here.

Wait for confirmation.

### 4. Write a stub config

Create `/data/config.json` with `init_complete: false` and `install_id` set:

```json
{
  "schema_version": 1,
  "install_id": "<from /data/install_id>",
  "init_complete": false,
  "bootstrap_completed_at": "<iso ts>"
}
```

This is the marker that `inbox-router` uses to know "we're between Phase 1 and Phase 2 — route everything to gtd-interview, not to a not-yet-existing Inbox."

### 5. Hand off

Print, in the user's terminal:

> ✓ Bootstrap done.
>
> **Next: open your Telegram bot and send `/gtd-config`. The rest of setup happens in chat.**
>
> Strongly recommended: use **Telegram Desktop** for the next phase — you'll be opening Google and Notion authorization links, and they need to open in a browser on this same computer (the OAuth redirects come back to `localhost:8000` here).
>
> Before you message the bot, start the long-running channel session so it's listening:
>
> ```
> exit
> docker compose exec -d assistant /app/bin/start-channel.sh
> docker compose exec assistant tail -f /data/channel.log   # optional, watch it work
> ```
>
> Then DM your bot `/gtd-config`.

Exit.

## Failure modes

- User skips a sub-step (e.g. doesn't pair) → next step's verification fails → re-prompt with the exact command to run, don't advance.
- `.env` missing Google client id/secret → record warning, continue (Google OAuth will fail later in the interview, at which point the user is told to fix `.env` and restart the channel session).
