# Quickstart

End-to-end setup on your laptop. **~20 minutes** if you already have a Google Cloud project, a Notion integration, and a Telegram bot. **~45 minutes** if you need to create them from scratch (each linked doc covers ~10 minutes).

## 0. Prerequisites

- **Docker** — Desktop on macOS/Windows, Engine on Linux. Verify: `docker --version`.
- **A claude.ai account** — required. The Telegram channel plugin only works with claude.ai login, not API keys (research preview limitation).
- **A Google Cloud project** — yours. See [`google-setup.md`](google-setup.md). 5 min.
- **A Notion integration token** — see [`notion-setup.md`](notion-setup.md). Optional but most jobs need it.
- **A Telegram bot** — see [`telegram-setup.md`](telegram-setup.md). Required for the inbox-everything UX.

## 1. Clone + configure

```bash
git clone https://github.com/gothamite/cgtd.git
cd cgtd
cp .env.example .env
$EDITOR .env  # paste GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET, NOTION_TOKEN
```

## 2. Start the container and log in to Claude

```bash
mkdir -p data         # ensures correct ownership before docker creates it root-owned (Linux footgun)
docker compose up -d
docker compose exec assistant claude
```

First session prompts `claude login` — complete OAuth in your browser. The credential persists in `./data/claude-home/` so you only do this once per install.

## 3. Install the Telegram channel plugin

Inside Claude Code:

```
/plugin marketplace list                # confirm the marketplace your account has access to
/plugin install telegram@<marketplace>  # default below assumes 'anthropic' — replace if /plugin list shows different
/telegram:configure                     # paste your bot token (NOT in .env — the plugin stores it itself)
/telegram:access                        # approve pairing after DMing your bot
/plugin list                            # confirm the install succeeded; copy the exact spec
```

The install argument is `<plugin-name>@<marketplace>`; the channel spec used later is `plugin:<plugin-name>@<marketplace>` — same `<marketplace>`, just prefixed with `plugin:`. If your marketplace name isn't `anthropic`, set `CGTD_CHANNEL_SPEC=plugin:telegram@<your-marketplace>` in `.env`.

Full Telegram walkthrough: [`telegram-setup.md`](telegram-setup.md).

## 4. Run /init-cgtd

In the same Claude Code session:

```
/init-cgtd
```

Walks you through:
1. Locale (en/ru/de) + timezone + display name.
2. Telegram chat_id confirmation (auto-detected from pairing).
3. Google OAuth — for each Gmail account you want to read. First one becomes your **primary**.
4. Auto-creates "Notion Inbox Attachments" folder on your primary account's Drive.
5. Notion DB URLs for Inbox / Next Actions / Tasks / Notes / 📦 Inbox Archive.
6. Schedule preset (flex / 9-to-5 / shift / custom).
7. Cron job enable/disable.

Init writes `./data/config.json`, copies default memory into `./data/memory/`, and arms the cron jobs.

## 5. Start the long-running channel session

So your bot can deliver Telegram messages 24/7:

```bash
docker compose exec -d assistant /app/bin/start-channel.sh
```

Logs:

```bash
docker compose exec assistant tail -f /data/channel.log
```

## 6. Test it

Send your bot any message — it should land in Notion Inbox with a 📥 reaction.

The slash commands below are recognized by the `inbox-router` skill (which the channel session loads automatically). You can run them either as Telegram messages to your bot, or in an interactive Claude Code session:

```bash
docker compose exec assistant claude
```

```
/morning      # runs morning-ritual immediately
/evening      # runs evening-review immediately
/inbox        # processes pending Notion Inbox entries
/status       # shows last-ok timestamps for each cron
```

If `/status` reports a cron hasn't fired in a while, see [`architecture.md` § Cron model](architecture.md#cron-model) for how Claude Code's cron system works and how missed-run catch-up happens at SessionStart.

## 7. Day-to-day

- Send anything to your Telegram bot — lands in Inbox.
- Morning brief at 08:30, inbox sweep every 2h, evening review at 21:30 (timezone from `config.user.timezone`).
- Replies to morning/evening prompts are matched and applied against `/data/pending-reviews.jsonl`.

## Editing skills (dev mode)

Override compose to bind-mount source skills so edits are live:

```yaml
# docker-compose.override.yml
services:
  assistant:
    volumes:
      - ./data:/data
      - ./skills:/app/skills
```

```bash
docker compose up -d
docker compose exec -d assistant /app/bin/start-channel.sh   # restart channel session
```

## Updating

```bash
git pull
docker compose build
docker compose up -d
docker compose exec -d assistant /app/bin/start-channel.sh
```

State (`./data/config.json`, memory, claude-home, logs) survives rebuilds.
