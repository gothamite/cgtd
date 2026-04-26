FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq python3 python3-pip pipx tini unzip \
    && rm -rf /var/lib/apt/lists/*

# uv / uvx for workspace-mcp
RUN pipx install uv && pipx ensurepath
ENV PATH="/root/.local/bin:${PATH}"

# Bun (used by Anthropic's official channel plugins)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Claude Code CLI (must be 2.1.80+ for channels)
RUN npm install -g @anthropic-ai/claude-code

# App
WORKDIR /app
COPY skills/   ./skills/
COPY memory/   ./memory/
COPY bin/      ./bin/
COPY .claude/  ./.claude/
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh ./bin/*.sh

# Wire skills + settings into in-container Claude install
RUN mkdir -p /root/.claude && ln -s /app/skills /root/.claude/skills

# Persistent state
ENV CGTD_DATA_DIR=/data
VOLUME ["/data"]

# OAuth callback for google-workspace MCP. Only needed during init/reauth.
EXPOSE 8000

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
CMD ["sleep", "infinity"]
