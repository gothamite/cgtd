# cgtd

A self-hosted, Telegram-driven GTD assistant powered by Claude Code. Your personal "AI secretary" that reads your Gmail/Calendar across multiple Google accounts, classifies inbound items into a Notion GTD system, plans your day around your rhythm, and chats with you in Telegram.

Built as opinionated, ready-to-run Docker containers — one container per assistant, fully isolated. Run multiple in parallel (work / personal / shared family inbox / etc.) on your laptop or on a $6 VPS.

## What it does (out of the box)

- **Inbox-everything pattern.** Send any Telegram message — text, photo, voice transcript, link — and it lands in your Notion **Inbox** by default. No commands required.
- **Nightly inbox processing.** Classifies each Inbox entry into Next Actions, Tasks (multi-step projects), or Notes (reference). Parses implicit deadlines («до конца зимы», "by next Friday", "EOM").
- **Morning brief (08:30).** Today's calendar, Gmail 24h actionable items, overdue Next Actions, and a proposed time-blocked plan around your weekly rhythm. Asks for your approval before scheduling.
- **Daytime sweep (every 2h).** Scans Gmail + Calendar across all your Google accounts; routes actionable items to Notion; pings you on urgent deadlines.
- **Evening review (21:30).** Walks through today's Next Actions, asks status, rolls unfinished items forward.
- **Multi-account Google.** Reads Gmail + Calendar from any number of Google accounts you authorize. One folder on your *primary* (personal) account's Drive is used for inbox attachments.
- **Multi-locale.** Russian, English, German built in. Pick at init.

## Quick start (local Docker)

```bash
git clone https://github.com/<you>/cgtd.git
cd cgtd
cp .env.example .env
# fill in .env (Google OAuth client + Notion token) — see docs/{google,notion}-setup.md
docker compose up -d
docker compose exec assistant claude
# first time → claude login (browser OAuth, claude.ai)
# inside Claude:  /plugin install telegram@<official-marketplace>
#                 /telegram:configure   (paste bot token)
#                 /telegram:access      (approve pairing after DMing your bot)
#                 /init-cgtd             (full interactive bootstrap)
docker compose exec -d assistant /app/bin/start-channel.sh
```

The init skill walks you through everything else (10 minutes): timezone, Telegram chat link, Google OAuth for each account, Drive folder, Notion DB URLs, schedule preset. When done, your assistant is live and the four cron jobs are armed; the channel session keeps the Telegram bot listening 24/7.

Full guide: [`docs/quickstart.md`](docs/quickstart.md).

## Deploy to a VPS (DigitalOcean, etc.)

A $6/month droplet runs one assistant 24/7. See [`docs/deploy-digitalocean.md`](docs/deploy-digitalocean.md).

## Multiple assistants on one host

Each container is its own assistant — own Telegram bot, own Google tokens, own Notion DBs, own data volume. See [`docs/multiple-assistants.md`](docs/multiple-assistants.md) for the parallel-deploy pattern.

## Prerequisites

- Docker (Desktop on macOS/Windows, Docker Engine on Linux)
- A claude.ai account (Telegram channel plugin requires it; API keys do not work for channels — research preview limitation)
- A Google Cloud project (yours — takes 5 min to create; see [`docs/google-setup.md`](docs/google-setup.md))
- A Notion account with an integration token (optional but recommended)
- A Telegram bot (required for the inbox-everything UX)

You bring your own credentials for everything. Nothing is shared with the project author.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for the full design: how skills, crons, MCP servers, and the data volume fit together; how isolation between containers works; what's *not* isolated and why.

## Adapt it

The shipped skills (`skills/morning-ritual`, `skills/proactive-inbox`, etc.) are plain Markdown files. Add your own — for example, a `workday-reminder` skill that pings you at 10:33 every weekday in your local language ([example in `docs/examples/workday-reminder.md`](docs/examples/workday-reminder.md)). Drop new SKILL.md files into `skills/`, rebuild the image (or use dev-mode bind mount), edit `config.json` to add a cron entry, and you're done.

## License

MIT. See [`LICENSE`](LICENSE).
