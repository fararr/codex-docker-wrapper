# Codex in Docker on macOS

A practical setup for running **Codex only inside Docker** on macOS, with local auth storage and access limited to directories you explicitly mount.

This version is written for **public GitHub / repo documentation**, so paths and examples are generic.

---

## Table of contents

- [What this setup gives you](#what-this-setup-gives-you)
- [How the safety model works](#how-the-safety-model-works)
- [Directory layout](#directory-layout)
- [1. Create the Dockerfile](#1-create-the-dockerfile)
- [2. Create docker-compose.yaml](#2-create-docker-composeyaml)
- [3. Create Codex config](#3-create-codex-config)
- [4. Create .gitignore](#4-create-gitignore)
- [5. Build the image](#5-build-the-image)
- [6. Authenticate Codex](#6-authenticate-codex)
- [7. Start Codex](#7-start-codex)
- [8. Open a shell in the container](#8-open-a-shell-in-the-container)
- [9. Resume a Codex session](#9-resume-a-codex-session)
- [10. Add more allowed directories later](#10-add-more-allowed-directories-later)
- [11. Recommended workflow](#11-recommended-workflow)
- [12. Safety habits](#12-safety-habits)
- [13. What “outside the sandbox” means](#13-what-outside-the-sandbox-means)
- [14. Known issues you may hit](#14-known-issues-you-may-hit)
- [15. Final notes](#15-final-notes)

---

## What this setup gives you

- Codex is **not installed natively** on macOS
- Codex runs **only inside Docker**
- auth/config is stored locally in `./coder/.codex`
- work happens in `./project_workspace`
- access is limited to **explicitly mounted directories**
- approval prompts stay enabled for riskier actions
- image and Codex CLI version are pinned
- PHP and Python tooling is available inside the container

---

## How the safety model works

The real safety boundary is:

1. **Docker container**
2. **Bind mounts**
3. **Codex approvals**

That means:

- Codex can access the container filesystem
- Codex can access only the host directories you mount into the container
- writable mounts can be changed, deleted, renamed, or git-modified
- approvals do **not** give Codex access to your whole Mac
- “outside the sandbox” does **not** mean outside Docker

### Practical conclusion

In this setup, Docker is the real containment layer.

Codex’s inner Linux sandbox may be unreliable in Docker Desktop, so the stable practical choice is:

- keep `approval_policy = "on-request"`
- keep `sandbox_mode = "workspace-write"`
- do **not** depend on Bubblewrap
- keep mounts narrow and explicit

---

## Directory layout

Example working directory:

```text
~/codex-docker
````

Recommended structure:

```text
~/codex-docker/
├── Dockerfile
├── Dockerfile.minimal
├── docker-compose.yaml
├── docker-compose.minimal.yaml
├── .gitignore
├── coder/
│   └── .codex/
│       ├── config.toml
│       └── auth.json
└── project_workspace/
```

### Meaning

* `Dockerfile` and `docker-compose.yaml` are the recommended full setup
* `Dockerfile.minimal` and `docker-compose.minimal.yaml` keep the older minimal variant
* `coder/.codex/` stores Codex config and auth on the host
* `project_workspace/` is the main writable workspace for Codex

---

## 1. Create the Dockerfile

Create `Dockerfile`:

```dockerfile
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
```

### Why this version

* uses stable Node LTS base image
* pins Codex CLI version
* includes practical PHP and Python CLI tooling
* uses the existing `node` user from the official image
* avoids UID/GID conflicts
* uses `tini` for cleaner process handling

---

## 2. Create docker-compose.yaml

Create `docker-compose.yaml`:

```yaml
services:
  codex:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        CODEX_VERSION: "0.118.0"

    image: codex-local:0.118.0
    container_name: codex-local

    working_dir: /workspace

    stdin_open: true
    tty: true

    user: "node"

    volumes:
      - ./project_workspace:/workspace
      - ./coder/.codex:/home/node/.codex

      # Optional read-only reference repo/example docs:
      # - ./reference_repo:/reference:ro

    environment:
      HOME: /home/node
      PYTHONDONTWRITEBYTECODE: "1"
      PYTHONUNBUFFERED: "1"

    security_opt:
      - no-new-privileges:true

    cap_drop:
      - ALL

    pids_limit: 256
    mem_limit: 4g
    cpus: 2.0

    restart: "no"

    command: ["codex"]
```

### What this does

* mounts `./project_workspace` as `/workspace`
* mounts `./coder/.codex` as `/home/node/.codex`
* runs as non-root user `node`
* drops extra Linux capabilities
* prevents privilege escalation
* keeps the container interactive and simple

---

## 3. Create Codex config

Create:

```text
coder/.codex/config.toml
```

Contents:

```toml
model = "gpt-5.4"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
cli_auth_credentials_store = "file"

[projects."/workspace"]
trust_level = "trusted"
```

### Meaning

* `model = "gpt-5.4"` sets the default model
* `approval_policy = "on-request"` asks before higher-risk actions
* `sandbox_mode = "workspace-write"` is the normal editing mode
* `cli_auth_credentials_store = "file"` stores auth in `.codex/auth.json`
* `trust_level = "trusted"` marks `/workspace` as a trusted project root

---

## 4. Create .gitignore

Create `.gitignore`:

```gitignore
coder/.codex/auth.json
coder/.codex/*.db
coder/.codex/logs/
```

This prevents local auth and transient state from being committed.

---

## 5. Build the image

From the project root:

```bash
docker compose build
```

---

## 6. Authenticate Codex

Use device auth:

```bash
docker compose run --rm codex codex login --device-auth
```

This is usually simpler than browser callback login inside Docker.

After login, auth is reused from:

```text
./coder/.codex/auth.json
```

So future runs are normally just:

```bash
docker compose run --rm codex
```

---

## 7. Start Codex

Start interactive Codex:

```bash
docker compose run --rm codex
```

Run a direct command:

```bash
docker compose run --rm codex codex --help
```

---

## 8. Open a shell in the container

Fresh shell:

```bash
docker compose run --rm codex bash
```

If the container is already running:

```bash
docker compose exec codex bash
```

Useful checks inside:

```bash
whoami
pwd
php -v
python3 --version
composer --version
codex --version
ls -la /workspace
ls -la /home/node/.codex
```

---

## 9. Resume a Codex session

Resume the most recent session:

```bash
docker compose run --rm codex resume --last
```

Resume a specific session:

```bash
docker compose run --rm codex resume YOUR_SESSION_ID
```

Example:

```bash
docker compose run --rm codex resume 013d2754-b870-72a2-38bc-5250df853335
```

---

## 10. Add more allowed directories later

If you want Codex to access more directories, mount them explicitly.

Example:

```yaml
volumes:
  - ./project_workspace:/workspace/project_workspace
  - ../another_repo:/workspace/another_repo
  - ./coder/.codex:/home/node/.codex
```

### Read-only reference mount

If Codex should only read a directory:

```yaml
- ../reference_repo:/workspace/reference_repo:ro
```

This is the safest way to provide reference access without allowing edits.

---

## 11. Recommended workflow

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

### Open shell

```bash
docker compose run --rm codex bash
```

### Resume last session

```bash
docker compose run --rm codex resume --last
```

---

## 12. Safety habits

### Use git in the workspace

Inside `project_workspace`:

```bash
cd project_workspace
git init
git add .
git commit -m "baseline before Codex"
```

This gives you a rollback point before Codex starts making changes.

### Keep mounts narrow

Good:

```yaml
- ./project_workspace:/workspace
```

Avoid mounting your whole home directory or large parent folders unless truly necessary.

### Use read-only mounts where possible

Example:

```yaml
- ../reference_repo:/workspace/reference_repo:ro
```

### Read approvals carefully

Usually reasonable to approve:

* edits you explicitly requested in `/workspace`
* local tests or formatters in the workspace
* normal source file creation and updates

Pause and inspect more carefully:

* package installs
* network-heavy actions
* mass deletes
* git commands with side effects
* anything mentioning unexpected paths

---

## 13. What “outside the sandbox” means

If Codex asks to run something “outside the sandbox”, that means:

* outside Codex’s **inner** sandbox
* but still **inside Docker**

It does **not** mean:

* outside the container
* full access to macOS
* automatic access to unmounted host paths

It still only has access to:

* container paths
* mounted directories
* container network

### Important rule

Approvals do **not** expand Docker’s mount boundary.

They only allow more action inside the boundaries the container already has.

---

## 14. Known issues you may hit

### Docker credential helper error

You may see an error like:

```text
error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH
```

Cause:

* Docker CLI is configured to use a missing credential helper

Fix:

* remove the stale `credsStore` entry from `~/.docker/config.json`

This is a Docker client problem, not a Codex auth problem.

---

### UID/GID 1000 conflict

You may see:

```text
groupadd: GID '1000' already exists
```

Cause:

* the official Node image already contains the `node` user/group using UID/GID 1000

Fix:

* do not create a custom user
* use the existing `node` user

That is why the final setup uses:

```dockerfile
USER node
ENV HOME=/home/node
```

---

### Bubblewrap / inner sandbox notes

Codex may use an OS-level local sandbox, but Bubblewrap availability inside Docker is environment-dependent.

Checks:

* `bwrap --version`
* minimal `bwrap` sandbox command
* `unshare -U true` to verify user namespaces

Common issues:

* namespace permission errors
* `Operation not permitted`
* `bwrap: Unknown option --argv0` (usually Bubblewrap version mismatch)

Practical decision for this Docker setup:

* do not depend on Bubblewrap
* keep Codex approvals enabled
* rely on Docker mounts and container restrictions as the main containment boundary

---

## 15. Final notes

This is the stable practical setup for Dockerized Codex on macOS:

* Codex runs only in Docker
* auth is stored locally in `./coder/.codex`
* work happens in `./project_workspace`
* access is limited to explicitly mounted directories
* approvals remain enabled
* Docker is the real containment layer
* Bubblewrap is intentionally not required in this setup
* PHP and Python tooling is included in the full image

### One-line summary

**Codex runs only inside Docker, reuses file-based auth from `./coder/.codex`, edits only explicitly mounted directories, and relies on Docker isolation plus approval prompts rather than a fragile inner Linux sandbox.**
