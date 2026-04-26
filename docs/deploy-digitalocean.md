# Deploy to a VPS (DigitalOcean / Hetzner / etc.)

A $6/month droplet runs one assistant 24/7. Total time: 20 minutes including OAuth.

## Provision

Any small Linux droplet works. Tested on:
- DigitalOcean: 1 vCPU / 1 GB RAM Basic droplet ($6/mo)
- Hetzner: CX11 (€4.51/mo)
- Any VPS with Ubuntu/Debian and Docker

```bash
# install Docker (Ubuntu 24.04)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
exec sudo -u $USER bash  # re-login for group
```

## Deploy

```bash
git clone https://github.com/<you>/cgtd.git
cd cgtd
cp .env.example .env
nano .env   # paste secrets
docker compose up -d
```

## OAuth on a remote droplet

The OAuth callback listens on `localhost:8000` *inside the container*. Your browser is on your laptop. Bridge them with SSH local-forward — only needed during `/init-cgtd` and `/cgtd-reauth`.

**On your laptop**, in one terminal:

```bash
ssh -L 8000:localhost:8000 user@droplet.example.com
# leave this open
```

In a second terminal (also on your laptop):

```bash
ssh user@droplet.example.com 'docker compose -f /path/to/cgtd/docker-compose.yml exec assistant claude'
```

Run `/init-cgtd`. When the Google OAuth URL appears, click it — your laptop browser opens, you authorize, the redirect lands on `localhost:8000` on your laptop, SSH forwards it to the droplet container. Done.

After init completes, drop the SSH tunnel; refresh tokens auto-renew silently.

## Locking down the droplet

- Comment out the `ports` section in `docker-compose.yml` after init — port 8000 only matters during OAuth, and you can re-add it temporarily for `/cgtd-reauth`. Or leave it bound to `127.0.0.1:8000` (default), which makes it inaccessible from outside the droplet.
- Use `ufw` or your provider's firewall to drop everything except SSH (22).
- The Telegram bot uses outbound HTTPS only — no inbound ports needed for it.

## Updating

```bash
ssh user@droplet
cd cgtd
git pull
docker compose build
docker compose up -d
```

State (`./data/config.json`, memory, logs) survives rebuilds.

## Backups

`./data/` is the entire state. Snapshot it nightly:

```bash
# add to root crontab
0 4 * * * tar -czf /var/backups/gtd-$(date +\%F).tar.gz /path/to/cgtd/data
```

Or use your provider's volume snapshot feature.

## Logging in to Claude on a headless droplet

`claude login` opens a browser for OAuth. On a headless VPS, use the same SSH local-forward pattern as the Google OAuth step — Claude Code's login flow runs a callback listener on a local port. Open the printed URL in your laptop browser; the redirect tunnels back through SSH.

If your VPS provider blocks browser logins entirely, the alternative is to do `claude login` once on your laptop, then copy `~/.claude/.credentials.json` to the droplet's `./data/claude-home/.credentials.json`. The credential is portable.

## Costs

- Droplet: $5–6/month.
- Claude usage: dominant cost. Depends on how chatty your assistant is. Rough estimate for the four shipped jobs: $10–30/month with Sonnet under a Claude Pro subscription, or proportional usage on Max. Tune the model inside the container if needed.
- Telegram, Notion, Google: free tier sufficient.
