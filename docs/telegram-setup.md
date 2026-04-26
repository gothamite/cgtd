# Telegram setup

The assistant uses Claude Code's **Telegram channel plugin** (research preview) — not a generic MCP. Channels are how Claude Code receives push events from external chat platforms; see https://code.claude.com/docs/en/channels-reference for the protocol.

After the terminal bootstrap installs and pairs the bot, **the entire rest of setup happens over Telegram chat** (`/gtd-config` skill). Use **Telegram Desktop** on the same computer that's running Docker — you'll be opening Google and Notion authorization links during the interview, and they need to land in a browser on the Docker host.

## Prerequisites

- Claude Code v2.1.80+ (already pinned in the Docker image).
- A claude.ai account. **API keys are not supported for channels** — channels require claude.ai OAuth login. Research-preview limitation.
- A Telegram bot. One bot per assistant; if you run two assistants, create two bots.

## Step 1 — create a bot (in Telegram)

1. Open Telegram, message [@BotFather](https://t.me/BotFather).
2. `/newbot` → display name + unique username (must end in `bot`).
3. BotFather replies with a token like `123456:ABC-DEF...`. Save it; you'll paste it into the channel plugin during Step 3 (not into `.env`).

## Step 2 — install the channel plugin (terminal bootstrap, Phase 1)

```bash
docker compose exec assistant claude
```

If first session ever, `claude login` runs — complete OAuth in your browser. Then inside Claude Code:

```
/plugin marketplace list                 # confirm your marketplace name
/plugin install telegram@<marketplace>   # default assumes 'anthropic'
```

After install:

```
/plugin list
```

Note the exact spec line (e.g. `plugin:telegram@anthropic`). If it's not the default, set in `.env`:

```
CGTD_CHANNEL_SPEC=plugin:telegram@<your-marketplace>
```

The install argument is `<plugin-name>@<marketplace>`. The channel spec used later by `start-channel.sh` is `plugin:<plugin-name>@<marketplace>` — same `<marketplace>`, prefixed with `plugin:`.

## Step 3 — configure the bot token

```
/telegram:configure
```

Paste your bot token when asked. The token is stored inside the plugin's data directory under `/data/claude-home/` and persists across container restarts.

## Step 4 — pair your Telegram account

The Telegram channel uses a sender allowlist to prevent prompt injection. Pair yourself:

1. In Telegram, DM your bot any message (e.g. "hi").
2. The bot replies with a pairing code.
3. In Claude Code, run `/telegram:access` and approve the pairing.

Now the bot only forwards messages from you to Claude. Anyone else who messages it is dropped silently.

## Step 5 — start the long-running channel session

Exit Claude Code and start the channel listener:

```bash
exit
docker compose exec -d assistant /app/bin/start-channel.sh
```

This runs `claude --channels <spec>` in a restart loop. Logs land in `/data/channel.log`:

```bash
docker compose exec assistant tail -f /data/channel.log
```

## Step 6 — finish setup over Telegram (Phase 2)

DM your bot:

```
/gtd-config
```

The bot interviews you over chat. See [`quickstart.md`](quickstart.md) Section 4 for the full walkthrough. Highlights:

- Language, name, timezone.
- Google OAuth per account (the bot sends links; click on Docker-host browser).
- Notion OAuth (the bot sends one link; pick which parent page to share during consent).
- Drive folder auto-creation.
- **GTD interview** — bot asks about your existing Notion layout, or creates the default for you. Generates a customized skill overlay matching your vocabulary.
- Schedule preset.
- Cron job toggles (each one explicit; no batch default).

When done, restart the channel session so the overlay loads:

```bash
docker compose restart assistant
docker compose exec -d assistant /app/bin/start-channel.sh
```

## Default routing behavior (post-init)

Once Phase 2 is complete, every inbound Telegram message is routed by the `inbox-router` skill:

- Plain text → Notion Inbox, react with 📥.
- Image / file → uploaded to your primary Google account's Drive folder, link added to the Inbox entry.
- `/morning`, `/evening`, `/inbox`, `/status`, `/gtd-config`, `/cgtd-reauth google <email>`, `/cgtd-reauth notion` → invoke the corresponding skill.
- Replies to morning/evening review prompts → matched against `/data/pending-reviews.jsonl` and applied.

## Troubleshooting

- **Bot replies but Inbox empty** — `/gtd-config` not yet completed. DM your bot `/gtd-config` to resume.
- **Bot doesn't reply at all** — channel session crashed. Check `/data/channel.log`. Common causes: Claude Code logged out (run `claude login` again), plugin uninstalled, bot token revoked.
- **"blocked by org policy"** when starting channel — your claude.ai org disabled channels. See https://code.claude.com/docs/en/channels#enterprise-controls.
- **OAuth link doesn't redirect** — Telegram Desktop on the Docker host machine opens links in the host's default browser; the redirect to `localhost:8000` works there. Mobile Telegram opens in the phone's browser, which can't reach localhost. Use Telegram Desktop on the Docker host for OAuth steps.
- **Two assistants, same bot** — don't. Each assistant needs its own bot, or messages collide.
