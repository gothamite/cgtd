# Architecture

## Components

```
┌─────────────────────────────────────────────────────────────────┐
│  Container (per assistant)                                       │
│                                                                  │
│  ┌──────────────┐    ┌────────────────────────────────────┐    │
│  │ Claude Code  │◄──►│ MCP servers (in-process or subproc) │    │
│  │ (CLI)        │    │  • google-workspace (uvx)           │    │
│  └──────┬───────┘    │  • notion (HTTP)                    │    │
│         │            │  • telegram (plugin)                │    │
│         ▼            └────────────────────────────────────┘    │
│  ┌──────────────┐                                                │
│  │ Skills       │  /app/skills — baked into image              │
│  │  • init      │  symlinked to /root/.claude/skills           │
│  │  • inbox-    │                                                │
│  │    router    │                                                │
│  │  • morning-  │                                                │
│  │    ritual    │                                                │
│  │  • evening-  │                                                │
│  │    review    │                                                │
│  │  • proactive-│                                                │
│  │    inbox     │                                                │
│  │  • process-  │                                                │
│  │    inbox     │                                                │
│  │  • cgtd-reauth│                                                │
│  └──────────────┘                                                │
│                                                                  │
│  ┌──────────────┐                                                │
│  │ /data (vol)  │  config.json, memory/, mcp/, cron-log.jsonl  │
│  │              │  pending-reviews.jsonl, lock/, install_id    │
│  └──────────────┘                                                │
└─────────────────────────────────────────────────────────────────┘
```

## Boot flow

1. `docker compose up` → `entrypoint.sh` runs.
2. Entrypoint creates `/data/{memory,mcp,lock}` if missing, generates `install_id` once, copies default memory if `/data/memory/MEMORY.md` is absent, links `~/.claude/.credentials.json` to `/data/.claude-credentials.json`.
3. Container idles on `sleep infinity`.
4. User runs `docker compose exec assistant claude` → opens an interactive Claude Code session.
5. SessionStart hook (defined in `.claude/settings.json.example`) reads `/data/config.json`. If absent → prints "run /init-cgtd". If present → reconciles crons + catches up missed runs.
6. Crons fire on schedule, invoke skills with `/app/bin/cron-log.sh start/lock/ok/fail` wrappers.

## State model

All persistent state is in `/data/`:

| Path | Purpose |
|------|---------|
| `install_id` | 8-char random slug, used in cron names |
| `config.json` | All user-specific config (single PII file) |
| `memory/` | Default + learned behavioral memories |
| `pending-reviews.jsonl` | Awaiting-user-reply state for morning/evening |
| `cron-log.jsonl` | Run history |
| `channel.log` | Long-running channel session log |
| `lock/<job>.lock` | Per-job mutex via `flock` |
| `mcp/google-workspace/` | OAuth refresh tokens, per email |
| `claude-home/` | Symlinked to `/root/.claude` — holds claude.ai credentials, installed plugins, plugin config (e.g. Telegram allowlist), per-install settings.json |

Nothing else outside `/data/` should be mutated at runtime. The image is read-only from the user's perspective.

## Authentication

**Claude Code is authenticated via `claude login` (claude.ai OAuth), not API key.** The Telegram channel plugin is part of Claude Code's "channels" research preview, which only works with claude.ai login. `ANTHROPIC_API_KEY` is intentionally not used.

The credential lands in `/data/claude-home/.credentials.json` after the first `claude login` and survives container rebuilds. Multiple containers running on the same host can each `claude login` independently — claude.ai allows multiple active sessions per account.

## Isolation model

**Strong (enforced by Docker):**
- Filesystem: each container sees only its own `/data` volume. No host path bleed.
- Network: each container has its own network namespace; MCP processes inside one container cannot reach another's.
- Process: separate PID namespace.
- Telegram: each container = one bot identity = one chat allowlist.
- Google tokens: cached in the container's `/data/mcp/`, never shared.

**Weak (convention only):**
- Both containers run as the same Unix user on the host. A privileged exploit could in theory cross containers — standard Docker threat model applies. Mitigation: don't run untrusted skill code, keep Docker patched.
- claude.ai account is shared if you log into the same account in multiple containers. Usage rolls up to that account. Acceptable for personal use.
- Google Cloud project may be shared (one client_id, multiple users via test-user list). Per-user tokens are still independent.

## Skill discovery

Inside the container, Claude Code reads skills from `~/.claude/skills/` (default location). The Dockerfile symlinks `/app/skills/` to `~/.claude/skills/`, so every SKILL.md in the repo is auto-discovered.

In dev mode (compose override with `./skills:/app/skills` bind mount), edits to skill files are live — the next session picks them up.

## Cron model

Crons are managed by Claude Code's built-in cron system (the `CronCreate` tool). They are scoped to the **claude.ai account**, not the container or the Unix host. The cron entry is stored on Anthropic's side and fires by spawning a Claude Code session that runs the configured prompt; the prompt invokes a skill, which uses `$CGTD_DATA_DIR=/data` to find its state. So a cron only does useful work while the container with the matching `/data` volume is reachable.

If the container is down or the channel session isn't running at fire time, the run is missed. The next SessionStart inside the container reads `cron-log.sh last-ok <job>` for each configured job; if a firing was expected more than `interval + 30 min` ago, it invokes the skill once with a catch-up note. Multiple missed intervals collapse to one catch-up — state has moved on.

**Debugging a cron that didn't fire:**
- Inside Claude Code: `CronList` shows everything, including failures. Filter by `cgtd-${install_id}-` prefix to see this install's jobs.
- Inside the container: `cat /data/cron-log.jsonl` is the run history. `/data/channel.log` shows the long-running channel session.
- `docker compose exec assistant /app/bin/cron-log.sh last-ok <job>` returns the ISO timestamp of the last successful run.
- Cron firing requires the channel session (or any Claude Code session inside this container) to be reachable. If `start-channel.sh` crashed, restart it: `docker compose exec -d assistant /app/bin/start-channel.sh`.

To list all crons created by a given install: `CronList` inside that container, or filter by name prefix `cgtd-${install_id}-` if you have multiple.

## Locale / i18n

`config.user.locale` (en/ru/de) controls all output. Skills read the locale at the top of each run and emit user-facing text accordingly. Internal logic, log lines, and JSON keys are always English.

## Why no global cron daemon

The container could run its own `cron` and shell out to `claude` for each job. That's an alternative design; the current design uses Claude Code's native crons, which lets the user manage schedules from inside Claude (`CronList`, `CronUpdate`) instead of editing crontabs. Tradeoff: requires Claude Code session/runtime to be reachable when the cron fires.
