---
name: init-cgtd
description: First-run interactive bootstrap. Creates /data/config.json, walks the user through timezone, Telegram, Google OAuth (multi-account), Notion DB IDs, schedule preset, and arms the cron jobs. Re-run any time to reconfigure.
---

# Init / reconfigure

Invoked manually as `/init-cgtd`. Runs interactively in the terminal where the user typed `claude`. Writes `/data/config.json`. Idempotent: re-running detects existing config and offers a per-section edit menu.

## Pre-flight

1. Read `/data/config.json` if it exists. If yes → present a numbered menu: «1) reconfigure user 2) reconfigure Telegram 3) reconfigure Google 4) reconfigure Notion 5) reconfigure schedule 6) reconcile crons 7) full re-init 0) exit». Branch to the chosen section. Otherwise proceed with full init below.
2. Read `install_id` from `/data/install_id` (entrypoint seeds it). Treat as immutable.
3. Read env vars: `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `NOTION_TOKEN`. Warn (don't abort) if any are missing — sections that need them will be skippable. **Do not** read `ANTHROPIC_API_KEY` (channels require claude.ai login, not API keys) or `TELEGRAM_BOT_TOKEN` (the bot token lives inside the Telegram channel plugin's own config, set via `/telegram:configure` — not in `.env`).

## Section 1 — user

Ask, in order:
- **Locale** — `en` / `ru` / `de`. Default `en`. Drives all subsequent prompt copy + skill output.
- **Display name** — first name only is fine.
- **Timezone** — auto-suggest from `cat /etc/timezone` or `TZ` env. Confirm.

## Section 2 — Telegram

- «Do you want a Telegram-driven inbox? [Y/n]». If `n` → set `telegram.enabled=false`, skip rest of section.
- The bot token is **not** in `.env`. The Telegram channel plugin stores it itself (set via `/telegram:configure`). If the user hasn't run `/plugin install telegram@<marketplace>`, `/telegram:configure`, and `/telegram:access` yet, point them at `docs/telegram-setup.md` Steps 2–4 and pause until they confirm the plugin is installed and a pairing exists.
- Ask the user to confirm their Telegram `chat_id` (visible in `/telegram:access` output, or as the `chat_id` attribute on inbound `<channel>` tags once the channel session is running).
- Save `chat_id`. Set `default_action` = `inbox`.

## Section 3 — Google

- Ask: «list every Gmail address you want this assistant to read (comma-separated). The first one will be your **primary** — its Drive holds the Inbox attachments folder».
- For each address, call `mcp__google-workspace__list_calendars user_google_email=<email>`. On first call per address, the server returns an OAuth URL. Print it. User clicks, authorizes in browser, redirect lands on `localhost:8000/oauth2callback` which is port-forwarded to the host. Wait for the user to confirm the browser said "authorization complete," then retry the call. On success, move to next address.
- If a port-forward isn't possible (remote VPS without SSH tunnel), point the user to `docs/deploy-digitalocean.md` § "OAuth on a remote droplet."
- Save accounts in `config.google.accounts[]`, `config.google.primary` = first.
- Auto-create Drive folder: `mcp__google-workspace__create_drive_folder folder_name="<config.google.drive_inbox_folder_name>"`, save the resulting `folder_id` to `config.google.drive_inbox_folder_id`.

## Section 4 — Notion

- «Do you use Notion for GTD? [Y/n]». If `n` → set `notion.enabled=false`. Without Notion, only `morning-ritual` (calendar) and `evening-review` (digest) remain useful — flag this.
- Otherwise: walk through `docs/notion-setup.md`: create a Notion integration, get the token, paste into `.env`, share four databases with the integration: **Inbox, Next Actions, Tasks, Notes**, and a page **📦 Inbox Archive**.
- Ask for the URL of each. Extract the data_source ID (the 32-char hex after the last `/` and before `?`). Validate by calling `mcp__notion__notion-fetch` on each ID — if it returns 404, ask again.
- Save IDs to `config.notion.{inbox,next_actions,tasks,notes,inbox_archive_page}_id`.

## Section 5 — schedule

- Ask: «pick a rhythm preset: 1) flex (no fixed hours, just morning + evening pings) 2) 9-to-5 office 3) shift work 4) custom». Default **flex**.
- For each preset, write `weekday_blocks` and `weekend_rule` accordingly. Custom = ask for blocks one by one (start, end, label).
- Ask which jobs to enable, with default cron expressions:
  - `proactive_inbox` — every 2h daytime (`13 8-20/2 * * *`)
  - `morning_ritual` — `30 8 * * *`
  - `evening_review` — `28 21 * * *`
  - `process_inbox` — `57 20 * * *`
- Allow per-job override of the cron expression for advanced users.

## Section 6 — write config + arm crons

1. Write `/data/config.json` atomically (`tmp` then `mv`).
2. Copy `/app/memory/.` into `/data/memory/` if not already there (entrypoint usually does this; double-check).
3. For each enabled job in `config.jobs`, call `CronCreate`:
   - `name` = `cgtd-${install_id}-${job}`
   - `cron` = the configured expression
   - `prompt` = `Invoke skill ${job}. install_dir=/data. Wrap with /app/bin/cron-log.sh start/lock/ok/fail.`
4. Run a **dry-run** of each enabled skill once with `--dry-run` flag (skill respects this and prints what it *would* do without writing). Report results to user.
5. Print: «✓ done. Your assistant is live. Send anything to your Telegram bot — it lands in your Notion Inbox by default. Daily brief at 08:30, evening review at 21:30, inbox sweep every 2h.»

## SessionStart reconciliation

When a new Claude Code session starts (e.g. user runs `docker compose exec gtd claude` again), the session reads `/data/config.json`. If `install_id` and config are present, it should:

1. `CronList` — for any of the configured `cgtd-${install_id}-*` jobs that are missing, recreate via `CronCreate`.
2. `cron-log.sh pending` → for each stale started run, `cron-log.sh fail` and (optionally) invoke the skill once with a catch-up note.
3. For each job, `cron-log.sh last-ok ${job}` — if a firing was missed by more than `interval + 30 min`, invoke the skill once with a catch-up note.
4. `cron-log.sh prune`.

The session should not run init again unless config is missing.

## Locale handling

Skill output (Telegram messages, terminal prompts) is in `config.user.locale`. Ship strings for `en`, `ru`, `de`. Default `en`. Don't hardcode Russian copy in skill files — read from a locale block in the skill's own SKILL.md or from `/app/memory/locales/${locale}.md` (see writing-skills convention).

## Failure modes

- Missing env var for a section → mark section incomplete in `config.json` (e.g. `notion.enabled=false`), continue. Init can be re-run later.
- OAuth callback unreachable → print explicit instructions for SSH local-forward (`ssh -L 8000:localhost:8000 <vps>`), pause until user retries.
- Notion DB URL invalid → ask again; offer link to `docs/notion-setup.md`.
