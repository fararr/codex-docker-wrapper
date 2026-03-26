FROM node:22.12.0-bookworm-slim

ARG CODEX_VERSION=0.116.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    less \
    procps \
    ripgrep \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex@${CODEX_VERSION} \
    && npm cache clean --force

RUN mkdir -p /workspace /home/node/.codex \
    && chown -R node:node /workspace /home/node

USER node
ENV HOME=/home/node
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["codex"]