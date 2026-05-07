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

Wait for the user to paste their `/plugin list` output or confirm verbally. If the marketplace differs from `claude-plugins-official`, tell them to substitute it on the command line when they start the channel session at the end of this skill.

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

### 4.5 Pre-flight MCP check

Before printing "✓ Bootstrap done", verify that both MCPs are reachable (not just not-yet-authed):

1. Call `mcp__google-workspace__list_calendars user_google_email=test@example.com`.
   - If it returns an OAuth URL → expected, everything is wired. Do not warn.
   - If it returns a tool-layer error (connection refused, server not found, non-200 that is not a redirect) → print in terminal: «⚠ google-workspace MCP is not responding. Check `data/claude-home/settings.json` and run `docker compose restart`.»

2. Call `mcp__notion__notion-search query=""`.
   - If it returns an OAuth URL or any valid response → expected. Do not warn.
   - If it returns a tool-layer error (network failure, unreachable server) → print: «⚠ Notion MCP is not responding. Check `data/claude-home/settings.json`.»

Auth errors (OAuth URL in the response body) are the normal pre-auth state — do not flag them. Only flag hard connection/configuration failures.

Continue to step 5 regardless (MCP issues can be fixed before the user runs `/gtd-config`).

### 5. Hand off

Print, in the user's terminal:

> ✓ Bootstrap done.
>
> **Next: open your Telegram bot and send `/gtd-config`. The rest of setup happens in chat.**
>
> Strongly recommended: use **Telegram Desktop** for the next phase — you'll be opening Google and Notion authorization links, and they need to open in a browser on this same computer (the OAuth redirects come back to `localhost:8000` here).
>
> Before you message the bot, exit this session and open a new one subscribed to the Telegram channel — it's the live Claude that will receive your messages:
>
> ```
> exit
> docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
> ```
>
> (Substitute your marketplace if it isn't `claude-plugins-official`.) Keep that terminal open — the channel session lives only while the terminal is up. Then DM your bot `/gtd-config` from Telegram Desktop.

Exit.

## Failure modes

- User skips a sub-step (e.g. doesn't pair) → next step's verification fails → re-prompt with the exact command to run, don't advance.
- `.env` missing Google client id/secret → record warning, continue (Google OAuth will fail later in the interview, at which point the user is told to fix `.env` and restart the container with `docker compose up -d`).
