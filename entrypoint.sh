#!/usr/bin/env bash
set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
mkdir -p "$DATA"/{memory,mcp/google-workspace,mcp/telegram,mcp/notion,lock,claude-home,skills-overlay}

# Persist Claude Code home (~/.claude) across container restarts.
# Holds: claude.ai OAuth credentials, installed plugins, plugin config, MCP tokens.
if [ ! -L /root/.claude ] || [ ! -d /root/.claude ]; then
  rm -rf /root/.claude
  ln -s "$DATA/claude-home" /root/.claude
fi

mkdir -p /root/.claude

# Skill resolution: per-skill overlay-first, baked-second.
# /app/skills/    — read-only templates shipped with the image
# /data/skills-overlay/ — user-customized SKILL.md files written by gtd-interview
# /root/.claude/skills/<name> resolves to the overlay version if present, else baked.
mkdir -p /root/.claude/skills
for skill_dir in /app/skills/*/; do
  name="$(basename "$skill_dir")"
  link="/root/.claude/skills/$name"
  rm -f "$link"
  if [ -f "$DATA/skills-overlay/$name/SKILL.md" ]; then
    ln -sfn "$DATA/skills-overlay/$name" "$link"
  else
    ln -sfn "$skill_dir" "$link"
  fi
done

# Per-install settings.json (MCP servers). Copy template if absent.
if [ ! -f "$DATA/claude-home/settings.json" ]; then
  cp /app/.claude/settings.json.example "$DATA/claude-home/settings.json"
fi

# Seed default memory on first run
if [ ! -f "$DATA/memory/MEMORY.md" ]; then
  cp -r /app/memory/. "$DATA/memory/"
fi

# Seed install_id
if [ ! -f "$DATA/install_id" ]; then
  head -c 4 /dev/urandom | xxd -p > "$DATA/install_id"
fi

exec "$@"
