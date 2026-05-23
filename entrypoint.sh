#!/usr/bin/env bash
set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
mkdir -p "$DATA"/{memory,mcp/google-workspace,mcp/telegram,mcp/notion,lock,claude-home,skills-overlay,cache/uv,cache/npm}

# Persist uvx/uv package cache so MCP servers start fast after container restarts.
# Without this, uvx re-downloads ~95 packages (~20 MB) each restart, hitting Claude Code's MCP init timeout.
if [ ! -L /root/.cache/uv ]; then
  rm -rf /root/.cache/uv
  mkdir -p /root/.cache
  ln -s "$DATA/cache/uv" /root/.cache/uv
fi

# Persist npm cache (used by npx for notion-mcp-server and other npm-based MCPs).
if [ ! -L /root/.npm ]; then
  rm -rf /root/.npm
  ln -s "$DATA/cache/npm" /root/.npm
fi

# Persist Claude Code home (~/.claude) across container restarts.
# Holds: claude.ai OAuth credentials, installed plugins, plugin config, MCP tokens.
if [ ! -L /root/.claude ] || [ ! -d /root/.claude ]; then
  rm -rf /root/.claude
  ln -s "$DATA/claude-home" /root/.claude
fi

mkdir -p /root/.claude

# Seed default memory into Claude's project memory path on first run.
# /root/.claude/projects/-app/memory/ is what Claude Code reads as auto-memory for the /app project.
mkdir -p /root/.claude/projects/-app/memory
if [ ! -f /root/.claude/projects/-app/memory/MEMORY.md ]; then
  cp -r /app/memory/. /root/.claude/projects/-app/memory/
fi

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

# Seed CLAUDE.md (session startup instructions) if absent.
if [ ! -f "$DATA/claude-home/CLAUDE.md" ]; then
  cp /app/.claude/CLAUDE.md "$DATA/claude-home/CLAUDE.md"
fi

# Seed default memory on first run
if [ ! -f "$DATA/memory/MEMORY.md" ]; then
  cp -r /app/memory/. "$DATA/memory/"
fi

# Seed install_id
if [ ! -f "$DATA/install_id" ]; then
  head -c 4 /dev/urandom | xxd -p > "$DATA/install_id"
fi

# Warn if container TZ doesn't match config.user.timezone
if [ -f "$DATA/config.json" ]; then
  cfg_tz=$(jq -r '.user.timezone // empty' "$DATA/config.json" 2>/dev/null)
  if [ -n "$cfg_tz" ] && [ "$cfg_tz" != "${TZ:-}" ]; then
    echo "⚠ TZ mismatch: container TZ=$TZ but config.user.timezone=$cfg_tz. Update TZ in docker-compose.yml and run 'docker compose up -d'."
  fi
fi

# Migrate Notion MCP from HTTP to stdio if needed
if [ -f "$DATA/claude-home/settings.json" ]; then
  notion_type=$(jq -r '.mcpServers.notion.type // empty' "$DATA/claude-home/settings.json" 2>/dev/null)
  if [ "$notion_type" = "http" ]; then
    jq '.mcpServers.notion = {"type":"stdio","command":"npx","args":["-y","@notionhq/notion-mcp-server"],"env":{"NOTION_API_KEY":"${NOTION_API_KEY}"}}' \
      "$DATA/claude-home/settings.json" > "$DATA/claude-home/settings.json.tmp" && \
      mv "$DATA/claude-home/settings.json.tmp" "$DATA/claude-home/settings.json" || \
      rm -f "$DATA/claude-home/settings.json.tmp"
    echo "✓ Notion MCP migrated to stdio in settings.json"
  fi
fi

# Resolve NOTION_API_KEY: prefer env var, fall back to config.json
if [ -z "${NOTION_API_KEY:-}" ] && [ -f "$DATA/config.json" ]; then
  cfg_notion_key=$(jq -r '.notion.api_key // empty' "$DATA/config.json" 2>/dev/null)
  if [ -n "$cfg_notion_key" ]; then
    export NOTION_API_KEY="$cfg_notion_key"
  fi
fi

exec "$@"
