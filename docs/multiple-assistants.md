# Multiple assistants on one host

Each assistant = one container = fully isolated state, MCP processes, Telegram bot, Google tokens, Notion DBs, cron jobs. The containers cannot read each other's data.

## Pattern: one compose file with multiple services

Use [`docker-compose.example.yml`](../docker-compose.example.yml) as a starting point. Two assistants ("work" and "personal"):

```bash
cp .env.example .env.work
cp .env.example .env.personal
nano .env.work       # work-specific secrets (different Telegram bot, different Notion DBs)
nano .env.personal   # personal secrets

docker compose -f docker-compose.example.yml up -d

docker compose -f docker-compose.example.yml exec work claude
# inside: /init-cgtd
docker compose -f docker-compose.example.yml exec personal claude
# inside: /init-cgtd
```

Each container gets its own `./data-work/` and `./data-personal/` volume.

## Checklist for a clean second assistant

- [ ] Separate Telegram bot (separate `TELEGRAM_BOT_TOKEN` in its `.env`).
- [ ] Separate Notion integration token (or the same one if both assistants share databases — usually you don't want this).
- [ ] Separate Notion databases (or the same parent workspace, different databases).
- [ ] Separate Google OAuth client? **Optional**. You can use the same Cloud project + same `client_id` for multiple containers — each container's tokens are independent. Use a different project only if you want hard quota / audit isolation between assistants.
- [ ] Different host port for OAuth callback (`8001`, `8002`, ...) so init flows don't collide.

## What's shared anyway

- Anthropic account. Same `ANTHROPIC_API_KEY` is fine across containers; usage rolls up to your account.
- Google Cloud project (if you reuse it). Token caches are still per-container.
- The host kernel and filesystem. A buggy or hostile skill in container A still cannot read container B's `/data` because Docker namespaces them, but both run as the same Unix user on the host. Standard container threat model — don't run untrusted skill code.

## Stopping a single assistant

```bash
docker compose -f docker-compose.example.yml stop work
docker compose -f docker-compose.example.yml rm work
rm -rf ./data-work
```

The other assistant keeps running.
