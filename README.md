# cgtd

A self-hosted, Telegram-driven GTD assistant powered by Claude Code. Your personal AI that classifies everything you throw at it into a Notion GTD system adapted to *your* layout, plans your day around your rhythm, and chats with you over Telegram.

Built as opinionated, ready-to-run Docker containers — one container per assistant, fully isolated. Run multiple in parallel (work / personal / family / etc.) on your laptop or on a $6 VPS.

**Google (Gmail / Calendar / Drive) is optional.** The system works fully with Notion alone.

## What it does

- **Inbox-everything.** Send any Telegram message — text, photo, link, voice memo — and it lands in your Notion Inbox. No commands required.
- **Nightly inbox processing (21:15).** Classifies each Inbox entry into Next Actions, Projects (multi-step), or Reference (notes). Parses implicit deadlines («до конца зимы», "by next Friday", "EOM"). Routes to the right Notion DB.
- **Nightly project processing (21:45).** Decomposes new projects into atomic Next Actions, flags stalled or deadline-at-risk projects, queues them for your approval.
- **Morning brief (08:30 weekday / 09:30 weekend).** Overdue items, today's calendar, Gmail 24h digest, and a proposed time-blocked plan. Asks for your approval before writing anything to Notion.
- **Daytime sweep (every 2h).** Scans Gmail + Calendar across all your Google accounts; routes actionable items to Notion; pings you on urgent deadlines. *(Google only)*
- **Evening review (21:28).** Walks through today's Next Actions, asks status, rolls unfinished items forward. Includes a 24h digest of Gmail + calendar.
- **Someday/Maybe daily review.** Every morning the assistant scans your deferred items, prioritises by Eisenhower matrix, and proposes the best ones for today's free slots.
- **Context stacking.** Batches @phone / @errands / @computer tasks into the same time slots. Works even without explicit context fields — the AI infers from task text.
- **Adapts to any Notion layout.** The setup interview discovers your existing databases (Inbox, actions, projects, notes — whatever you call them), maps their status values, and rewrites its own skills to match your vocabulary. If you have nothing yet, it creates a default layout.
- **AI persona.** During setup you can give the assistant a character — name, tone, personality. Optional; no default persona if declined.
- **Multi-account Google.** Reads Gmail + Calendar from any number of Google accounts. One Drive folder on your primary account holds files you forward to the bot. *(optional)*
- **Multi-locale.** Russian, English, German. Pick during setup.

## Services

| Service | Required? | Purpose |
|---|---|---|
| **Notion** | Yes | GTD system lives here |
| **Telegram** | Yes | Entire UI after the terminal bootstrap |
| **Google** (Gmail / Calendar / Drive) | Optional | Email + calendar digest, file attachments |

You bring your own credentials for all of them. Nothing is shared with the project author.

## Quick start (local Docker)

You'll work in **three places**:

| Where | What runs there | How to enter |
|---|---|---|
| **Host shell** | git, docker, file editing | Your normal terminal |
| **In-container Claude Code** | `/init-cgtd` — terminal bootstrap | `docker compose exec assistant claude` |
| **Telegram** | `/gtd-config` interview, daily use | DM your bot once bootstrap is done |

**1. Host shell** — clone, configure, start:
```bash
git clone https://github.com/gothamite/cgtd.git
cd cgtd
cp .env.example .env
# If using Google: paste GOOGLE_OAUTH_CLIENT_ID + GOOGLE_OAUTH_CLIENT_SECRET
# NOTION_API_KEY is optional here — you can set it during /gtd-config instead
nano .env
mkdir -p data            # prevents root-owned dir on Linux
docker compose up -d
```

**2. In-container Claude Code** — terminal bootstrap (one-time):
```bash
docker compose exec assistant claude
```
First run prompts `claude login` (browser OAuth). Then inside Claude:
```
/init-cgtd
```
Installs the Telegram channel plugin, configures the bot token, pairs your Telegram account. When it prints "✓ Bootstrap done" — exit.

> The bootstrap checks that Google and Notion MCPs are reachable. If either isn't, you'll see a warning — fix `data/claude-home/settings.json` and `docker compose restart` before proceeding.

**3. Host shell** — start the long-running channel session:
```bash
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

**4. Telegram** — finish setup:
DM your bot `/gtd-config`. The rest — locale, timezone, Google OAuth, Notion token, Drive folder, GTD interview, schedule, cron jobs — happens in chat.

> **Use Telegram Desktop** on the same computer running Docker. Google and Notion auth links redirect to `localhost:8000` on the Docker host.

Full guide: [`docs/quickstart.md`](docs/quickstart.md).

## Time budget

- **~20 minutes** if Notion workspace, Telegram bot, and (optionally) Google Cloud project are already created.
- **~45 minutes** if creating them from scratch.

## Slash commands

| Command | What it does |
|---|---|
| `/gtd-config` | Run / continue / reconfigure the setup interview |
| `/cgtd-reauth google <email>` | Re-authorize a Google account when its token expires |
| `/cgtd-reauth notion` | Update the Notion API token |
| `/morning` or `/утро` | Trigger the morning brief now |
| `/evening` or `/вечер` | Trigger the evening review now |
| `/inbox` or `/разбери` | Process the Notion Inbox now |
| `/tasks-processing` | Decompose new projects and check active ones now |
| `/status` | Show last-ok timestamps for each cron job |
| `/cgtd-timezone <tz>` | Update the timezone (e.g. `Europe/Berlin`) |

Any plain message (no `/`) drops into your Notion Inbox.

## Deploy to a VPS

A $6/month droplet runs one assistant 24/7. See [`docs/deploy-digitalocean.md`](docs/deploy-digitalocean.md).

## Multiple assistants on one host

Each container is its own assistant — own Telegram bot, own Google tokens, own Notion workspace, own data volume. See [`docs/multiple-assistants.md`](docs/multiple-assistants.md).

## Prerequisites

- Docker (Desktop on macOS/Windows, Engine on Linux)
- A [claude.ai](https://claude.ai) account (Telegram channel plugin requires it; API keys don't work for channels)
- A Notion account + Internal Integration Token ([`docs/notion-setup.md`](docs/notion-setup.md) — 5 min)
- A Telegram bot via BotFather ([`docs/telegram-setup.md`](docs/telegram-setup.md) — 5 min)
- *(Optional)* A Google Cloud project with OAuth credentials ([`docs/google-setup.md`](docs/google-setup.md) — 10 min)

## Architecture

See [`docs/architecture.md`](docs/architecture.md): how skills, crons, MCP servers, and the data volume fit together; how isolation between containers works; how skill overlays adapt to your Notion layout.

## Adapting further

Skills are plain Markdown files in `skills/`. The Telegram interview already customises them to your Notion vocabulary, writing personalised copies into `/data/skills-overlay/`. For deeper changes, edit files in `skills/` and rebuild — example in [`docs/examples/workday-reminder.md`](docs/examples/workday-reminder.md).

## License

MIT. See [`LICENSE`](LICENSE).
