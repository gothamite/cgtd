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

Walk the user through, in order. **Important nuance:** `telegram:configure` and `telegram:access` are skills shipped by the Telegram channel plugin — they are user-invocable as slash commands but you (the in-container Claude session running this skill) should also invoke them yourself via the `Skill` tool when reaching steps 2 and 3, so the user just answers the prompts you relay rather than typing `/telegram:configure` themselves and switching context.

A side note for the user: while the Telegram channel plugin is installed but not yet paired, the in-container Claude session may surface `Telegram MCP` connection errors. These are **expected** during this window — ignore them and continue.

### 1. Install the Telegram channel plugin

Plugin install is something only the user can do (it requires interactive plugin marketplace UI). Print:

> First, install the Telegram channel plugin. Run these commands here:
> ```
> /plugin marketplace list
> /plugin install telegram@<marketplace>
> /plugin list
> ```
> The default marketplace is `claude-plugins-official`. If `/plugin list` shows your Telegram spec under a different marketplace, tell me the exact spec.

Wait for the user to paste their `/plugin list` output or confirm verbally. If the marketplace differs from `claude-plugins-official`, instruct them to set `CGTD_CHANNEL_SPEC=plugin:telegram@<their-marketplace>` in `.env` (host shell, then `docker compose up -d` to reload).

### 2. Configure the bot token

Invoke the `telegram:configure` skill via the `Skill` tool: `Skill(skill="telegram:configure")`. The plugin's skill prompts the user for the bot token and stores it under `/data/claude-home/`. Don't ask the user to type `/telegram:configure` themselves — just invoke and let it run.

If the plugin reports the token already exists, confirm with the user whether to keep or replace.

### 3. Pair your Telegram account

Tell the user (in plain text):
> Now DM your bot from Telegram — any message will do. The plugin generates a pairing code and surfaces it through the next skill we run.

Then invoke `Skill(skill="telegram:access")`. The plugin's skill walks the user through approving the pairing code that the channel emits when their first DM arrives. Wait for the skill to report success.

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
