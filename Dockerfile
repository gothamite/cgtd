FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq python3 python3-pip pipx tini unzip \
      procps \
    && rm -rf /var/lib/apt/lists/*
# procps provides `pkill`/`ps`/`kill` — needed for any user debugging that
# involves listing or killing processes inside the container.

# uv / uvx for workspace-mcp
RUN pipx install uv && pipx ensurepath
ENV PATH="/root/.local/bin:${PATH}"

# Bun (used by Anthropic's official channel plugins)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Claude Code CLI — pinned. Channels require 2.1.80+. Bump intentionally;
# floating "latest" risks a silent breaking change between rebuilds.
ARG CLAUDE_CODE_VERSION=2.1.83
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"

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
