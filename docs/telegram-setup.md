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
/plugin install telegram@<marketplace>   # default is 'claude-plugins-official'
```

After install:

```
/plugin list
```

Note the exact spec line (e.g. `plugin:telegram@claude-plugins-official`). You'll paste it on the command line when you start the channel session in Step 5. The install argument is `<plugin-name>@<marketplace>`; the channel spec is `plugin:<plugin-name>@<marketplace>` — same `<marketplace>`, prefixed with `plugin:`.

## Step 3 — configure the bot token

When you run `/init-cgtd` (next section), the cgtd init skill **invokes the `telegram:configure` skill for you** via Claude Code's Skill tool — you don't need to type `/telegram:configure` yourself. Just answer the bot-token prompt that appears.

If you want to (re-)run it standalone outside of `/init-cgtd`, you can also invoke it directly: ask Claude to "configure the Telegram channel" or use `/telegram:configure`. The token is stored inside the plugin's data directory under `/data/claude-home/` and persists across container restarts.

> **Note:** while the plugin is installed but not yet paired, the in-container Claude session may show "Telegram MCP" connection errors. That's expected during this window — the channel plugin can't connect until pairing is complete. Ignore the errors and continue.

## Step 4 — pair your Telegram account

The Telegram channel uses a sender allowlist to prevent prompt injection. The cgtd `/init-cgtd` skill handles this for you — invokes the `telegram:access` skill and prompts you to DM your bot. Specifically:

1. The init skill invokes `telegram:access`.
2. It tells you to DM your bot any message (e.g. "hi") from Telegram.
3. The plugin generates a pairing code; the access skill surfaces it and asks for your approval.
4. Once approved, the bot only forwards messages from you to Claude. Anyone else messaging it is dropped silently.

## Step 5 — start the channel session

Exit Claude Code, then open a new in-container session subscribed to the Telegram channel:

```bash
exit                                                                                  # back to host
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

(Substitute the marketplace if yours isn't `claude-plugins-official`.) This is your **live** Claude session — every Telegram message sent to your bot will appear in this terminal as a `<channel source="telegram" ...>` tag, and Claude will process it. Keep the terminal open.

> **Lifetime note.** This session lives only as long as the terminal is open. Close the terminal and the bot stops responding. For 24/7 operation, run on a VPS in `tmux`/`screen`, or keep the terminal open with the laptop on (e.g. macOS users with "prevent sleeping" enabled in Energy settings can leave the session running while the lid is closed).

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

When done, exit the current channel session (Ctrl+C in the terminal where it's running) and start a new one so the overlay loads:

```bash
docker compose exec -it assistant claude --channels plugin:telegram@claude-plugins-official
```

## Default routing behavior (post-init)

Once Phase 2 is complete, every inbound Telegram message is routed by the `inbox-router` skill:

- Plain text → Notion Inbox, react with 📥.
- Image / file → uploaded to your primary Google account's Drive folder, link added to the Inbox entry.
- `/morning`, `/evening`, `/inbox`, `/status`, `/gtd-config`, `/cgtd-reauth google <email>`, `/cgtd-reauth notion` → invoke the corresponding skill.
- Replies to morning/evening review prompts → matched against `/data/pending-reviews.jsonl` and applied.

## Troubleshooting

- **Bot replies but Inbox empty** — `/gtd-config` not yet completed. DM your bot `/gtd-config` to resume.
- **Bot doesn't reply at all** — channel session crashed or terminal closed. Check the terminal where you ran `claude --channels …`. Common causes: Claude Code logged out (run `claude login` again), plugin uninstalled, bot token revoked, terminal closed by accident.
- **"blocked by org policy"** when starting channel — your claude.ai org disabled channels. See https://code.claude.com/docs/en/channels#enterprise-controls.
- **OAuth link doesn't redirect** — Telegram Desktop on the Docker host machine opens links in the host's default browser; the redirect to `localhost:8000` works there. Mobile Telegram opens in the phone's browser, which can't reach localhost. Use Telegram Desktop on the Docker host for OAuth steps.
- **Two assistants, same bot** — don't. Each assistant needs its own bot, or messages collide.
