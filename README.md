# cgtd

A self-hosted, Telegram-driven GTD assistant powered by Claude Code. Your personal AI assistant that reads your Gmail/Calendar across multiple Google accounts, classifies inbound items into a Notion GTD system adapted to *your* layout, plans your day around your rhythm, and chats with you in Telegram.

Built as opinionated, ready-to-run Docker containers — one container per assistant, fully isolated. Run multiple in parallel (work / personal / shared family inbox / etc.) on your laptop or on a $6 VPS.

## What it does (out of the box)

- **Inbox-everything pattern.** Send any Telegram message — text, photo, voice transcript, link — and it lands in your Notion **Inbox** by default. No commands required.
- **Nightly inbox processing.** Classifies each Inbox entry into Next Actions, Tasks (multi-step projects), or Notes (reference). Parses implicit deadlines («до конца зимы», "by next Friday", "EOM").
- **Morning brief (08:30).** Today's calendar, Gmail 24h actionable items, overdue Next Actions, and a proposed time-blocked plan around your weekly rhythm. Asks for your approval before scheduling.
- **Daytime sweep (every 2h).** Scans Gmail + Calendar across all your Google accounts; routes actionable items to Notion; pings you on urgent deadlines.
- **Evening review (21:30).** Walks through today's Next Actions, asks status, rolls unfinished items forward.
- **Multi-account Google.** Reads Gmail + Calendar from any number of Google accounts you authorize. One folder on your *primary* (personal) account's Drive holds files you forward to the bot.
- **Adapts to your Notion layout.** During setup over Telegram, the assistant interviews you about your existing GTD setup — what you call "Inbox," your Status values, whether you use a priority scheme — and rewrites its skills to match your vocabulary. If you don't have a setup yet, it creates the default one for you.
- **Multi-locale.** Russian, English, German built in. Pick during setup.

## Required services

- **Notion** — GTD system lives here.
- **Google** (Gmail / Calendar / Drive) — input + attachment storage.
- **Telegram** — the entire UI after the initial bootstrap.

You bring your own credentials for all three. Nothing is shared with the project author.

## Quick start (local Docker)

You'll be working in **three places**. Knowing which is which avoids confusion:

| Where | What runs there | How to enter |
|---|---|---|
| **Host shell** (your laptop's terminal) | git, docker, file editing | Just your normal terminal |
| **In-container Claude Code** | `/init-cgtd` and other skills; sees the cgtd MCPs | `docker compose exec assistant claude` |
| **Telegram chat with your bot** | `/gtd-config` interview, daily use | DM your bot once Phase 1 is done |

Steps:

**1. Host shell** — clone, configure, start the container:
```bash
git clone https://github.com/gothamite/cgtd.git
cd cgtd
cp .env.example .env
$EDITOR .env             # paste GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET
mkdir -p data            # prevent root-owned dir on Linux
docker compose up -d
```

**2. In-container Claude Code** — terminal bootstrap (Phase 1):
```bash
docker compose exec assistant claude    # entered from host shell; opens Claude Code inside the container
```
First time prompts `claude login` (browser OAuth). Then inside Claude:
```
/init-cgtd
```
This walks you through three things only: install the Telegram channel plugin, configure the bot token, pair your account. When it prints "✓ Bootstrap done" and tells you to exit — exit.

**3. Host shell** — start the long-running channel session:
```bash
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

**4. Telegram chat** — finish setup (Phase 2):
DM your bot `/gtd-config`. The rest — locale, timezone, Google OAuth per account, Notion OAuth, Drive folder, GTD interview, schedule, cron jobs — happens in chat.

> **Use Telegram Desktop** on the same computer running Docker. You'll be opening Google and Notion authorization links, and they need to land in a browser on the Docker host (the OAuth redirects come back to `localhost:8000` there).

> **Note on host-side Claude Code:** if you have Claude Code installed on your laptop and want it to drive Steps 1 and 3 for you, that's fine — but those host-side steps are just shell commands. The cgtd skills (`/init-cgtd`, `/gtd-config`, etc.) only exist *inside* the container. Don't try to run them from a host-side Claude session.

Full guide: [`docs/quickstart.md`](docs/quickstart.md).

## Time budget

- **~25 minutes** if your Google Cloud project, Notion workspace, and Telegram bot are already created.
- **~50 minutes** if you're creating them from scratch (each linked doc covers one prerequisite in ~10 min).

## Slash commands (handled by `inbox-router`)

| Command | What it does |
|---|---|
| `/gtd-config` | Re-run / continue the Telegram interview |
| `/cgtd-reauth google <email>` | Re-authorize a Google account when its token expires |
| `/cgtd-reauth notion` | Re-authorize Notion |
| `/morning`, `/evening` | Trigger the corresponding skill on demand |
| `/inbox` | Process the Notion Inbox now |
| `/status` | Show last-ok timestamps for each cron job |

Plain Telegram messages (no `/`) drop into your Notion Inbox.

## Deploy to a VPS (DigitalOcean, etc.)

A $6/month droplet runs one assistant 24/7. See [`docs/deploy-digitalocean.md`](docs/deploy-digitalocean.md).

## Multiple assistants on one host

Each container is its own assistant — own Telegram bot, own Google tokens, own Notion DBs, own data volume. See [`docs/multiple-assistants.md`](docs/multiple-assistants.md).

## Prerequisites

- Docker (Desktop on macOS/Windows, Engine on Linux)
- A claude.ai account (Telegram channel plugin requires it; API keys do not work for channels — research preview limitation)
- A Google Cloud project (yours — 5 min; see [`docs/google-setup.md`](docs/google-setup.md))
- A Notion account (no token needed; OAuth happens during the Telegram interview)
- A Telegram bot (5 min via BotFather; see [`docs/telegram-setup.md`](docs/telegram-setup.md))

## Architecture

See [`docs/architecture.md`](docs/architecture.md): how skills, crons, MCP servers, and the data volume fit together; how isolation between containers works; what's *not* isolated and why; how skill overlays adapt to your GTD layout.

## Adapt it further

The shipped skills are plain Markdown files. The Telegram interview already adapts them to your Notion vocabulary (writing customized copies into `/data/skills-overlay/`). For deeper changes, drop new SKILL.md files into `skills/` and rebuild the image — example in [`docs/examples/workday-reminder.md`](docs/examples/workday-reminder.md).

## License

MIT. See [`LICENSE`](LICENSE).
