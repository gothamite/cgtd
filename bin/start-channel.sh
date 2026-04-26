#!/usr/bin/env bash
# Long-running Claude Code session that listens for Telegram channel events.
# Run via:  docker compose exec -d assistant /app/bin/start-channel.sh
#
# Restarts on crash. Logs to /data/channel.log. Tail with:
#   docker compose exec assistant tail -f /data/channel.log

set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
LOG="$DATA/channel.log"

# Channel plugin spec — verify the exact name with `/plugin list` after install.
# Default assumes the official Telegram channel from Anthropic's marketplace.
CHANNEL_SPEC="${CGTD_CHANNEL_SPEC:-plugin:telegram@anthropic-official}"

while true; do
  echo "[$(date -u +%FT%TZ)] starting claude with channel: $CHANNEL_SPEC" >> "$LOG"
  claude --channels "$CHANNEL_SPEC" >> "$LOG" 2>&1 || true
  echo "[$(date -u +%FT%TZ)] claude exited, restarting in 5s" >> "$LOG"
  sleep 5
done
