# Telegram setup

The assistant uses Claude Code's **Telegram channel plugin** (research preview), not a generic MCP. Channels are how Claude Code receives push events from external chat platforms — see https://code.claude.com/docs/en/channels-reference for the protocol.

## Prerequisites

- Claude Code v2.1.80+ (already pinned in the Docker image).
- A claude.ai account. **API keys are not supported for channels** — channels require claude.ai OAuth login. This is a research-preview limitation.
- A Telegram bot. One bot per assistant; if you run two assistants, create two bots.

## Step 1 — create a bot

1. Open Telegram, message [@BotFather](https://t.me/BotFather).
2. `/newbot` → display name + unique username (must end in `bot`).
3. BotFather replies with a token like `123456:ABC-DEF...`. Save it.

## Step 2 — install the channel plugin (inside the container)

```bash
docker compose exec assistant claude
```

If it's your first session ever, Claude Code prompts `claude login` — complete the OAuth flow in your browser (see `docs/architecture.md` § Authentication for VPS/headless variants).

Once logged in, in Claude Code:

```
/plugin install telegram@anthropic
```

The exact marketplace identifier may evolve during the research preview. Run `/plugin list` after install to verify the spec, then put that exact spec into the `CGTD_CHANNEL_SPEC` env var (see Step 5).

## Step 3 — configure the bot token

The Telegram channel plugin ships with a `/telegram:configure` skill:

```
/telegram:configure
```

Paste your bot token when asked. The token is stored inside the plugin's data directory (under your container's `/data/claude-home/`, which persists across restarts).

## Step 4 — pair your Telegram account

The Telegram channel uses a sender allowlist to prevent prompt injection. Pair yourself:

1. In Telegram, DM your bot any message (e.g. "hi").
2. The bot replies with a pairing code.
3. In Claude Code, run `/telegram:access` and approve the pairing.

Now the bot only forwards messages from you to Claude. Anyone else who messages the bot is dropped silently.

## Step 5 — finish bootstrap (run /init-cgtd)

In the same Claude Code session, run the bootstrap:

```
/init-cgtd
```

The init skill auto-detects the existing Telegram pairing and asks you to confirm the chat_id. It then walks you through Google OAuth, Notion, and the schedule preset. See [`quickstart.md`](quickstart.md) Step 4 for the full walkthrough.

`/init-cgtd` must run **before** the long-running channel session — otherwise crons aren't armed and the inbox-router has no Notion DB IDs to route to.

## Step 6 — start the long-running channel session

With config in place, start the channel listener:

```bash
docker compose exec -d assistant /app/bin/start-channel.sh
```

This runs `claude --channels <spec>` in a restart loop. Logs land in `/data/channel.log`:

```bash
docker compose exec assistant tail -f /data/channel.log
```

If your plugin spec differs from the default (`plugin:telegram@anthropic`), set it in `.env`:

```
CGTD_CHANNEL_SPEC=plugin:telegram@<your-marketplace>
```

The install argument format is `<plugin-name>@<marketplace>`; the channel spec format is `plugin:<plugin-name>@<marketplace>`. Same `<marketplace>` value, just prefixed with `plugin:`.

After the channel session is up, send your bot any message — it should land in your Notion Inbox with a 📥 reaction.

## Default routing behavior

Once Telegram is configured, every inbound message is routed by the `inbox-router` skill:

- Plain text → Notion Inbox, react with 📥.
- Image / file → uploaded to your primary Google account's Drive folder, link in the Inbox entry.
- `/morning`, `/evening`, `/inbox`, `/status`, `/init-cgtd`, `/cgtd-reauth <email>` → invoke the corresponding skill.
- Replies to morning/evening review prompts → matched against `/data/pending-reviews.jsonl` and applied.

## Troubleshooting

- **Bot replies but Inbox empty** — `/init-cgtd` not yet run, so `notion.inbox_id` is unset. Run init.
- **Bot doesn't reply at all** — channel session crashed. Check `/data/channel.log`. Common causes: Claude Code logged out (run `claude login` again), plugin uninstalled, bot token revoked.
- **"blocked by org policy"** when starting channel — your claude.ai org disabled channels. See https://code.claude.com/docs/en/channels#enterprise-controls.
- **Two assistants, same bot** — don't. Each assistant needs its own bot, or messages collide.
