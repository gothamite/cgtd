# Quickstart

End-to-end setup. **~25 minutes** if all prerequisites exist; **~50 minutes** from scratch.

## Three places you'll be working

Each step in this doc is labeled with one of these tags so you always know where to type:

- **`[host]`** — your laptop's normal terminal. Runs git, docker, your editor.
- **`[claude-in-container]`** — Claude Code running *inside* the cgtd container. Has access to the cgtd skills (`/init-cgtd`, `/gtd-config`, etc.) and the project's MCPs. Entered with `docker compose exec assistant claude`.
- **`[telegram]`** — chat with your bot in the Telegram app.

**Heads-up:** if you have Claude Code installed on your laptop too, you might be tempted to run cgtd skills there. Don't — the skills only exist inside the container. A host-side Claude can help you type the `[host]` steps if you want, but it can't run `/init-cgtd` or `/gtd-config`.

## Two-phase install flow

- **Phase 1 (terminal)** — Docker, Claude Code login, Telegram channel plugin, bot pairing. Mostly `[host]` with one `[claude-in-container]` excursion for `/init-cgtd`.
- **Phase 2 (Telegram chat)** — everything else: locale, Google OAuth, Notion OAuth, Drive folder, GTD interview, schedule, crons. All `[telegram]`.

## 0. Prerequisites

- **Docker** — Desktop on macOS/Windows, Engine on Linux. Verify: `docker --version`.
- **A claude.ai account** — required. The Telegram channel plugin only works with claude.ai login, not API keys (research preview limitation).
- **A Google Cloud project** — yours. See [`google-setup.md`](google-setup.md). 5 min.
- **A Notion account** — no token to paste; OAuth happens during the Telegram interview. The interview can also create the GTD databases for you if you don't have any yet. See [`notion-setup.md`](notion-setup.md) for what gets created and how access restriction works.
- **A Telegram bot** — see [`telegram-setup.md`](telegram-setup.md). Required.

## 1. Clone + configure  `[host]`

```bash
git clone https://github.com/gothamite/cgtd.git
cd cgtd
cp .env.example .env
$EDITOR .env  # paste GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET
```

That's the only secrets you need in `.env`. Notion and Telegram are configured later (Notion via OAuth in Phase 2; Telegram bot token via the channel plugin's own `/telegram:configure`).

## 2. Start the container and log in to Claude  `[host]` → `[claude-in-container]`

```bash
mkdir -p data                            # [host] — prevents root-owned dir on Linux
docker compose up -d                     # [host]
docker compose exec assistant claude     # [host] — this command opens Claude Code INSIDE the container
```

That last command leaves you sitting at a Claude Code prompt that's running *inside* the container. From this point until you `exit`, every `/command` you type is `[claude-in-container]`.

First session prompts `claude login` — complete OAuth in your browser. The credential persists in `./data/claude-home/`.

## 3. Phase 1 — terminal bootstrap  `[claude-in-container]`

At the in-container Claude Code prompt:

```
/init-cgtd
```

The skill walks you through:

1. **Install the Telegram channel plugin** — `/plugin marketplace list`, then `/plugin install telegram@<your-marketplace>`. The default marketplace is `claude-plugins-official`; if `/plugin list` shows something different, substitute it on the command line in Step 3 below where you start the channel session.
2. **Configure the bot token** — `/telegram:configure`, paste the BotFather token. (The plugin stores the token itself — not in `.env`.)
3. **Pair your Telegram account** — `/telegram:access`, DM your bot, approve the pairing.

When the skill prints "✓ Bootstrap done", `exit` Claude Code (back to `[host]`), then open a new in-container Claude session subscribed to the Telegram channel:

```bash
exit                                                                                  # [claude-in-container] → drops you back to [host]
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official        # [host]
```

**Keep this terminal open.** It holds your live channel session — every Telegram message to the bot will appear here as a `<channel source="telegram" ...>` tag, and Claude will process it. Close the terminal and the bot stops responding (and crons can't fire).

> **GUI alternative (Docker Desktop):** Containers → click `cgtd` → **Exec** tab → in the shell that opens, run `claude --channels plugin:telegram@claude-plugins-official`. Same effect as the CLI command above; the session lives as long as Docker Desktop is running and that Exec tab is open.

> For 24/7 operation: run on a VPS, or keep the laptop on with sleep disabled. macOS users: System Settings → Energy → "Prevent automatic sleeping when display is off" lets the channel keep running with the lid closed. (Future versions of cgtd may include `tmux`-based detach/reattach, but for now the channel session is tied to its terminal.)

## 4. Phase 2 — Telegram chat  `[telegram]`

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

When done, the bot tells you to restart the channel session so the new skill overlay loads. Back in `[host]`:

```bash
docker compose restart assistant                                # [host]
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official      # [host]
```

## 5. Verify  `[telegram]` or `[claude-in-container]`

Send your bot any message — it should land in your Notion Inbox with a 📥 reaction.

For deeper checks, run any of these as Telegram messages, or open a fresh in-container Claude session (`[host]`: `docker compose exec assistant claude`) and run them there:

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
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official   # restart channel session
```

Edits to `./skills/*` are live; edits to `/data/skills-overlay/*` always win when both exist.

## Updating

```bash
git pull
docker compose build
docker compose up -d
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

State (`./data/config.json`, `data/skills-overlay/`, memory, claude-home, logs) survives rebuilds.
