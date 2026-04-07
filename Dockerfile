FROM node:24-bookworm-slim

ARG CODEX_VERSION=0.118.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    composer \
    curl \
    fd-find \
    git \
    jq \
    less \
    make \
    patch \
    php-cli \
    php-curl \
    php-intl \
    php-mbstring \
    php-sqlite3 \
    php-xml \
    php-zip \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    shellcheck \
    sqlite3 \
    tini \
    tree \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex@${CODEX_VERSION} \
    && npm cache clean --force

RUN mkdir -p /workspace /home/node/.codex /home/node/.local/bin \
    && chown -R node:node /workspace /home/node

USER node

ENV HOME=/home/node
ENV PATH=/home/node/.local/bin:/usr/local/bin:/usr/bin:/bin
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /workspace

RUN php -v \
    && composer --version \
    && python3 --version \
    && codex --version

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["codex"]