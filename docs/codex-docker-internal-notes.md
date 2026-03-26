# Codex in Docker on macOS — Internal Notes

This document complements the public `README.md` with a few more practical notes, context from setup failures, and safer operating habits for private/internal use.

---

## Purpose

Use this when you want the fuller rationale behind the setup, not just the final copy-paste commands.

The target setup is:

- Codex runs only inside Docker
- auth is stored in `./coder/.codex`
- writable work happens in `./project_workspace`
- access is limited by explicit bind mounts
- Docker is the real isolation boundary
- Codex approvals remain enabled
- Bubblewrap is not used in this setup

---

## Final host layout

Example local directory:

```text
~/codex-docker
```

Structure:

```text
~/codex-docker/
├── Dockerfile
├── docker-compose.yaml
├── .gitignore
├── coder/
│   └── .codex/
│       ├── config.toml
│       └── auth.json
└── project_workspace/
```

---

## Final file set

### Dockerfile

```dockerfile
FROM node:22.12.0-bookworm-slim

ARG CODEX_VERSION=0.116.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
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
```

### docker-compose.yaml

```yaml
services:
  codex:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        CODEX_VERSION: 0.116.0

    image: codex-local:0.116.0
    container_name: codex-local
    stdin_open: true
    tty: true
    working_dir: /workspace

    volumes:
      - ./project_workspace:/workspace
      - ./coder/.codex:/home/node/.codex

    security_opt:
      - no-new-privileges:true

    cap_drop:
      - ALL

    pids_limit: 256
    mem_limit: 4g
    cpus: 2.0

    command: ["codex"]
```

### coder/.codex/config.toml

```toml
model = "gpt-5.4"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
cli_auth_credentials_store = "file"

[projects."/workspace"]
trust_level = "trusted"
```

### .gitignore

```gitignore
coder/.codex/auth.json
coder/.codex/*.db
coder/.codex/logs/
```

---

## Why this exact design

### 1. No native Codex install

The point is to keep Codex off the host and make Docker the runtime boundary.

### 2. File-based auth

`cli_auth_credentials_store = "file"` keeps credentials in `./coder/.codex/auth.json` instead of using host keychain integration.

### 3. Use the built-in `node` user

The official Node image already ships with a `node` user, so reusing it avoids UID/GID collisions.

### 4. Keep mounts explicit

The Docker bind mounts are the real allowlist. If it is not mounted, Codex cannot access it from the container.

### 5. Do not depend on Bubblewrap

Bubblewrap was unreliable in this Docker Desktop environment, so the stable solution is to rely on Docker isolation and approvals instead.

---

## Authentication note

The reliable login flow was:

```bash
docker compose run --rm codex codex login --device-auth
```

This avoided the awkward browser callback flow from inside Docker.

After that, normal use is just:

```bash
docker compose run --rm codex
```

---

## What “outside the sandbox” really means

When Codex says it wants to run something “outside the sandbox”, it means outside Codex’s inner sandbox only.

It still remains:

- inside the same Docker container
- limited to the container filesystem
- limited to mounted host paths
- limited to the container’s network access

So this does **not** mean “outside Docker” and does **not** mean “full host access”.

---

## What approvals actually allow

Approvals do not expand mount access.

They do allow more action inside already-mounted writable directories, including:

- create files
- overwrite files
- delete files
- move or rename files
- modify git state

That is why the real protection is the mount list plus careful approval review.

---

## Safer operating habits

### Keep the writable workspace small

Prefer:

```yaml
- ./project_workspace:/workspace
```

instead of exposing broad parent directories.

### Use read-only mounts for references

Example:

```yaml
- ../reference_repo:/workspace/reference_repo:ro
```

### Commit a baseline before using Codex

```bash
cd project_workspace
git init
git add .
git commit -m "baseline before Codex"
```

### Inspect risky approvals

Read more carefully before approving:

- package installs
- network-heavy actions
- large deletes
- git commands with side effects
- commands referencing unexpected paths

---

## Errors hit during setup

### Docker credential helper error

Example:

```text
error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH
```

Meaning:

- Docker was configured to use a missing credential helper

Fix used:

- remove the stale `credsStore` entry from `~/.docker/config.json`

### UID/GID conflict

Example:

```text
groupadd: GID '1000' already exists
```

Meaning:

- the Node image already contains user/group `node` with UID/GID 1000

Fix used:

- stop creating a custom user
- use `USER node`

### Bubblewrap issues

Examples included namespace permission failures and:

```text
bwrap: Unknown option --argv0
```

Practical resolution:

- do not install `bwrap`
- keep approvals enabled
- rely on Docker as the stable boundary

---

## Typical workflow

### First-time setup

```bash
mkdir -p coder/.codex project_workspace
docker compose build
docker compose run --rm codex codex login --device-auth
```

### Daily use

```bash
docker compose run --rm codex
```

### Open a shell

```bash
docker compose run --rm codex bash
```

### Resume the last session

```bash
docker compose run --rm codex resume --last
```

### Resume a specific session

```bash
docker compose run --rm codex resume YOUR_SESSION_ID
```

---

## Short internal summary

This setup is intentionally simple:

- Docker is the main security boundary
- bind mounts define what Codex can reach
- approvals control higher-risk actions
- `project_workspace` is the writable working area
- `coder/.codex` stores auth/config locally
- Bubblewrap is not part of the final setup
