#!/usr/bin/env bash
set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
mkdir -p "$DATA"/{memory,mcp/google-workspace,mcp/telegram,mcp/notion,lock,claude-home}

# Persist Claude Code home (~/.claude) across container restarts.
# This holds: claude.ai OAuth credentials, installed plugins, plugin config.
# Without persistence, you'd re-login and re-install plugins on every recreate.
if [ ! -L /root/.claude ] || [ ! -d /root/.claude ]; then
  rm -rf /root/.claude
  ln -s "$DATA/claude-home" /root/.claude
fi

# Re-establish skills symlink (always points at the baked /app/skills, even after
# /root/.claude got replaced with the persisted volume above).
mkdir -p /root/.claude
[ -L /root/.claude/skills ] || ln -sfn /app/skills /root/.claude/skills

# Per-install settings.json (MCP servers + hooks). Copy template if absent so user
# can edit it later without losing changes on rebuild.
if [ ! -f "$DATA/claude-home/settings.json" ]; then
  cp /app/.claude/settings.json.example "$DATA/claude-home/settings.json"
fi

# Seed default memory on first run
if [ ! -f "$DATA/memory/MEMORY.md" ]; then
  cp -r /app/memory/. "$DATA/memory/"
fi

# Seed install_id (used by cron names + telemetry)
if [ ! -f "$DATA/install_id" ]; then
  head -c 4 /dev/urandom | xxd -p > "$DATA/install_id"
fi

exec "$@"
