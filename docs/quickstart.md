# Quickstart

End-to-end setup on your laptop. ~20 minutes.

## 0. Prerequisites

- **Docker** — Desktop on macOS/Windows, Engine on Linux. Verify: `docker --version`.
- **A claude.ai account** — required. The Telegram channel plugin only works with claude.ai login, not API keys (research preview limitation).
- **A Google Cloud project** — yours. See [`google-setup.md`](google-setup.md). 5 min.
- **A Notion integration token** — see [`notion-setup.md`](notion-setup.md). Optional but most jobs need it.
- **A Telegram bot** — see [`telegram-setup.md`](telegram-setup.md). Required for the inbox-everything UX.

## 1. Clone + configure

```bash
git clone https://github.com/<you>/cgtd.git
cd cgtd
cp .env.example .env
$EDITOR .env  # paste GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET, NOTION_TOKEN
```

## 2. Start the container and log in to Claude

```bash
docker compose up -d
docker compose exec assistant claude
```

First session prompts `claude login` — complete OAuth in your browser. The credential persists in `./data/claude-home/` so you only do this once per install.

## 3. Install the Telegram channel plugin

Inside Claude Code:

```
/plugin install telegram@<official-marketplace>
/telegram:configure        # paste your bot token
/telegram:access           # approve pairing after DMing your bot
```

Verify with `/plugin list`. Note the exact plugin spec — if it differs from the default, set `CGTD_CHANNEL_SPEC` in `.env`.

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

In another Claude Code session:

```bash
docker compose exec assistant claude
```

```
/morning      # runs morning-ritual immediately
/inbox        # processes pending Notion Inbox entries
/status       # shows last-ok timestamps for each cron
```

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
