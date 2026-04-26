# Quickstart

End-to-end setup. **~25 minutes** if all prerequisites exist; **~50 minutes** from scratch.

The install flow has two phases:

- **Phase 1 (terminal)** — Docker, Claude Code login, Telegram channel plugin, bot pairing.
- **Phase 2 (Telegram chat)** — everything else: locale, Google OAuth, Notion OAuth, Drive folder, GTD interview, schedule, crons.

## 0. Prerequisites

- **Docker** — Desktop on macOS/Windows, Engine on Linux. Verify: `docker --version`.
- **A claude.ai account** — required. The Telegram channel plugin only works with claude.ai login, not API keys (research preview limitation).
- **A Google Cloud project** — yours. See [`google-setup.md`](google-setup.md). 5 min.
- **A Notion account** — no token to paste; OAuth happens during the Telegram interview. The interview can also create the GTD databases for you if you don't have any yet. See [`notion-setup.md`](notion-setup.md) for what gets created and how access restriction works.
- **A Telegram bot** — see [`telegram-setup.md`](telegram-setup.md). Required.

## 1. Clone + configure

```bash
git clone https://github.com/gothamite/cgtd.git
cd cgtd
cp .env.example .env
$EDITOR .env  # paste GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET
```

That's the only secrets you need in `.env`. Notion and Telegram are configured later (Notion via OAuth in Phase 2; Telegram bot token via the channel plugin's own `/telegram:configure`).

## 2. Start the container and log in to Claude

```bash
mkdir -p data         # prevents root-owned dir on Linux
docker compose up -d
docker compose exec assistant claude
```

First session prompts `claude login` — complete OAuth in your browser. The credential persists in `./data/claude-home/`.

## 3. Phase 1 — terminal bootstrap

Inside Claude Code, run:

```
/init-cgtd
```

The skill walks you through:

1. **Install the Telegram channel plugin** — `/plugin marketplace list`, then `/plugin install telegram@<your-marketplace>`. The default assumes `anthropic`; if `/plugin list` shows different, set `CGTD_CHANNEL_SPEC=plugin:telegram@<your-marketplace>` in `.env`.
2. **Configure the bot token** — `/telegram:configure`, paste the BotFather token. (The plugin stores the token itself — not in `.env`.)
3. **Pair your Telegram account** — `/telegram:access`, DM your bot, approve the pairing.

When the skill prints "✓ Bootstrap done", exit Claude Code and start the long-running channel session:

```bash
exit
docker compose exec -d assistant /app/bin/start-channel.sh
docker compose exec assistant tail -f /data/channel.log    # optional, watch it work
```

## 4. Phase 2 — Telegram chat

Open **Telegram Desktop** on the same computer that's running Docker. (You can use mobile Telegram for the chat, but Google and Notion authorization links must be opened in a browser on the Docker host — Telegram Desktop on that host is the smoothest path.)

DM your bot:

```
/gtd-config
```

The bot interviews you over chat. In order:

1. **Language, name, timezone.**
2. **Why we need a primary Google account** — explanation: it's where files you forward to the bot get uploaded.
3. **Google OAuth, per account.** The bot sends you authorization links, one per Gmail address. Click each on the Docker host browser; the redirect lands on `localhost:8000` and the bot moves to the next.
4. **Notion OAuth.** One link. When Notion asks "which pages do you want to share?", **share only the parent page that holds (or will hold) your GTD databases.** Everything else stays private — Notion enforces this server-side.
5. **Drive folder** — auto-created on your primary account's Drive (`Notion Inbox Attachments`).
6. **GTD interview** — the bot asks if you already have a Notion GTD setup:
   - **No?** It creates the default layout for you (Inbox + Next Actions + Tasks + Notes + Inbox Archive page) under a parent you choose.
   - **Yes?** It asks for the URLs of your existing databases, probes their schemas, and asks about your Status values, priority scheme, and day-to-day workflow. Based on your answers, it writes customized skill files into `/data/skills-overlay/` so every skill speaks your vocabulary.
7. **Schedule** — pick a rhythm preset (flex / 9-to-5 / shift / custom).
8. **Cron jobs** — toggle each one explicitly (no batch "enable all" default).

When done, the bot tells you to restart the channel session so the new skill overlay loads:

```bash
docker compose restart assistant
docker compose exec -d assistant /app/bin/start-channel.sh
```

## 5. Verify

Send your bot any message — it should land in your Notion Inbox with a 📥 reaction.

For deeper checks, run any of these as Telegram messages or in `docker compose exec assistant claude`:

```
/morning      # runs morning-ritual immediately
/evening      # runs evening-review immediately
/inbox        # processes pending Notion Inbox entries
/status       # shows last-ok timestamps for each cron
```

If `/status` reports a cron hasn't fired in a while, see [`architecture.md` § Cron model](architecture.md#cron-model).

## 6. Day-to-day

- Send anything to your Telegram bot — lands in Inbox.
- Forward photos / PDFs / voice — file goes to your primary Drive folder, link in the Inbox entry.
- Morning brief at the time you configured, inbox sweep every 2h, evening review in the evening (timezones from `config.user.timezone`).
- Replies to morning/evening prompts get matched against `/data/pending-reviews.jsonl` and applied automatically.

## Editing skills (dev mode)

The Telegram interview writes customizations to `/data/skills-overlay/`. For deeper edits to the *templates*, override compose to bind-mount source skills:

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

Edits to `./skills/*` are live; edits to `/data/skills-overlay/*` always win when both exist.

## Updating

```bash
git pull
docker compose build
docker compose up -d
docker compose exec -d assistant /app/bin/start-channel.sh
```

State (`./data/config.json`, `data/skills-overlay/`, memory, claude-home, logs) survives rebuilds.
