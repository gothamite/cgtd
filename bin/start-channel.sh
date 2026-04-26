#!/usr/bin/env bash
# Long-running Claude Code session that listens for Telegram channel events.
# Run via:  docker compose exec -d assistant /app/bin/start-channel.sh
#
# Why `script`: claude --channels expects an interactive TTY. `docker compose exec -d`
# doesn't allocate one, which makes claude default to --print mode and exit immediately
# with "Input must be provided either through stdin...". `script -qc` allocates a pseudo-
# TTY and runs claude inside it — output still pipes to our log.
#
# Restarts on crash. Logs to /data/channel.log. Tail with:
#   docker compose exec assistant tail -f /data/channel.log

set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
LOG="$DATA/channel.log"

# Channel plugin spec — verify the exact name with `/plugin list` after install.
# Anthropic's official marketplace is currently `claude-plugins-official`.
CHANNEL_SPEC="${CGTD_CHANNEL_SPEC:-plugin:telegram@claude-plugins-official}"

# Lock — prevent multiple loops if invoked twice
LOCK="$DATA/lock/start-channel.lock"
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[$(date -u +%FT%TZ)] another start-channel.sh is already running, exiting" >> "$LOG"
  exit 0
fi

while true; do
  echo "[$(date -u +%FT%TZ)] starting claude with channel: $CHANNEL_SPEC" >> "$LOG"
  # script -q -c "<cmd>" /dev/null  → run <cmd> under a pty, suppress 'Script started' banner.
  # /dev/null target file means we don't double-record output (we capture via the redirect).
  script -qc "claude --channels '$CHANNEL_SPEC'" /dev/null >> "$LOG" 2>&1 || true
  echo "[$(date -u +%FT%TZ)] claude exited, restarting in 5s" >> "$LOG"
  sleep 5
done
