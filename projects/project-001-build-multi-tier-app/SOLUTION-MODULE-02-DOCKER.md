# SOLUTION — Module 2 — Application Code & Docker

> **Cloud Engineer Capstone — Multi-Tier Application Build**
> Module 2 of 11. Containerises a three-tier web application (Postgres + Flask + nginx) on a Raspberry Pi 5, ending with a single `docker-compose.yml` that brings the whole stack up with one command.

---

## TL;DR

We took a three-tier web application and packaged it into containers. The database tier uses the official `postgres:15` image with a bind-mounted `init.sql` for schema and seed data. The backend is a minimal Flask app talking to Postgres via `psycopg2`, packaged in a single-stage Dockerfile using `python:3.11.10-slim` as the base, running as a non-root user with `tini` as PID 1. The frontend is a static HTML page served by `nginx:alpine`, with a reverse proxy forwarding `/api/*` requests to the backend, built using a multi-stage Dockerfile that pre-compresses assets in a throwaway builder stage.

The three tiers are wired together by a single `docker-compose.yml` at the project root. Compose creates a private bridge network, runs an embedded DNS server, and resolves service names automatically — so the backend reaches the database at the hostname `database`, and nginx reaches the backend at `backend`, without any of the manual `--add-host` or `--network host` flags that were used during incremental development. Secrets are kept out of git via the `.env` / `.env.example` pattern. Data persists across container removal via a named volume.

By the end of the module, the entire stack — three containers, one private network, one named volume, healthcheck-gated startup ordering — comes up with **one command**: `docker compose up -d --build`. The user-facing behaviour is identical to running the three containers manually, but the deployment specification lives in a single version-controlled YAML file. That's the deliverable.

---

## What This Module Builds

```
solution/
├── docker-compose.yml          ← the deployment spec for the whole stack
├── .env.example                ← secrets contract (committed)
├── .env                        ← actual secrets (gitignored)
│
├── docker/
│   ├── database/
│   │   └── init.sql            ← schema + 3 seed rows
│   │
│   ├── backend/
│   │   ├── app.py              ← Flask: /api/health + /api/data
│   │   ├── requirements.txt    ← pinned deps
│   │   ├── Dockerfile          ← slim, non-root, tini PID 1, healthcheck
│   │   └── .dockerignore
│   │
│   └── frontend/
│       ├── index.html          ← calls /api/data, renders messages
│       ├── nginx.conf          ← reverse proxy + dual-stack listen
│       ├── Dockerfile          ← multi-stage: alpine builder → nginx:alpine
│       └── .dockerignore
│
├── tests/
│   └── backend/
│       └── test_health.py      ← trivial smoke test for the CI/CD module
│
└── terraform/                  ← unchanged from Module 1
```

---

## Build Order — Bottom-Up

| Step | What | Why this order |
|---|---|---|
| 1 | Pre-flight checks + Docker cleanup | Establish a known-good environment before any work begins. The Pi had accumulated 4.5GB of cruft from previous labs — cleaned via `docker system prune -a -f` |
| 2 | Project scaffold (`docker/` + `tests/` directories with `.gitkeep` placeholders) | Get the directory structure committed before any code lands, so each subsequent step has a clear destination |
| 3 | **Database tier** (`init.sql` + verify postgres:15 on ARM64) | Bottom of the dependency chain. Nothing else can be built or tested without it. Verifying the postgres image runs ARM64-native (`aarch64-unknown-linux-gnu`) catches architecture issues at the start |
| 4 | **Backend application code** (Flask, requirements.txt, smoke test) | Pure code with no container yet. Verifying the app runs against the live postgres proves the contract works before we wrap it |
| 5 | **Backend Dockerfile + `.dockerignore`** | Now that the app is proven, wrap it. Multiple platform-engineering decisions land in this step: non-root user, layer caching, tini, HEALTHCHECK |
| 6 | **Frontend code** (`index.html` + `nginx.conf`) | Static HTML + nginx config. The reverse-proxy pattern in `nginx.conf` is the platform-engineering heart of the frontend tier |
| 7 | **Frontend Dockerfile (multi-stage) + `.dockerignore`** | Demonstrates the multi-stage pattern with a real builder job (gzip pre-compression), not contrived validation |
| 8 | **`docker-compose.yml`** + `.env` pattern | Replaces every manual `docker run` flag with a single declarative file. The big simplification |

**Build-in-dependency-order principle.** Each tier was built and verified in isolation before the next tier consumed it. Postgres was proven on ARM64 before any code touched it. Flask was run bare-metal against postgres before being containerised. The backend container was proven to work before the frontend reverse-proxy was tested against it. Each step removed one variable from the next step's debugging surface.

---

## Step-by-Step Walkthrough

### Step 1 — Pre-flight checks and cleanup

The Pi had been used for unrelated labs and was carrying 4.5GB of stale Docker artifacts: stopped containers, unused images, orphaned networks. Before starting Module 2, the host was cleaned via:

```bash
docker system prune -a -f
docker volume prune -f
```

`docker system prune` removes stopped containers, unused networks, dangling images, and the build cache. It does **not** touch volumes by default (volumes contain data — Docker assumes opt-in for destruction). `docker volume prune` is a separate, deliberate step.

Disk recovered: 4.45 GB. Final `docker system df` showed zeros across the board.

**Pre-flight verifications:** Architecture (`uname -m` → `aarch64`), Docker version (29.2.1), Compose v2 plugin available, buildx available, ports 5000/5432/8080 free, ≥2GB free disk, ≥1GB available memory.

### Step 2 — Project scaffold

Created `solution/docker/{frontend,backend,database}/` and `solution/tests/backend/` with `.gitkeep` placeholders so git tracked the empty directories. Each placeholder was deleted in the step that added real files for that directory.

### Step 3 — Database tier

Wrote `solution/docker/database/init.sql` — schema for a single `messages` table plus three seed rows. The script uses `CREATE TABLE IF NOT EXISTS` and `INSERT ... ON CONFLICT DO NOTHING` so it is safe to re-run.

The postgres image automatically executes any SQL files mounted into `/docker-entrypoint-initdb.d/` **on first startup against an empty data directory.** Once the data directory is populated, the directory is ignored. This is fine for portfolio scope. In production, schema changes go through proper migration tools (Flyway, Alembic, Liquibase).

Verified the image runs ARM64-native on the Pi by starting a throwaway container with `--rm` and running `SELECT version()` — confirmed `aarch64-unknown-linux-gnu` in the output. PostgreSQL 15.17 on Debian 13.

### Step 4 — Backend application

Three files written:

- **`app.py`** — Flask app with two endpoints: `/api/health` (returns 200 always; deliberately does not check the database, so a transient DB blip doesn't fail liveness) and `/api/data` (queries postgres, returns JSON). Config is entirely env-var-driven. Logs to stdout. Listens on `0.0.0.0:5000`.
- **`requirements.txt`** — Three pinned dependencies (`flask==3.0.3`, `psycopg2-binary==2.9.9`, `pytest==8.3.3`).
- **`test_health.py`** — A single pytest case that confirms `/api/health` returns 200. Exists so the CI/CD module (a later module in the series) has something to invoke. Real test coverage is application-team responsibility.

**Contract verification, not testing.** Before writing the Dockerfile, the app was run directly on the Pi in a virtualenv against the live postgres container. Three contract points verified:

1. `pip install -r requirements.txt` runs to completion with no errors (same command the Dockerfile will run)
2. `python app.py` launches Flask, listens on `:5000`, logs to stdout (same command the Dockerfile's CMD will run)
3. `curl http://localhost:5000/api/data` returns three messages — proving env vars (`DB_HOST=localhost`, `DB_PASSWORD=...`) drive the connection and the DB integration works

**This is platform-engineering work, not testing.** The point is to verify the contract before baking it into a container, not to test the application logic. App-team CI runs the test suite; the platform engineer verifies that the contract holds before packaging.

### Step 5 — Backend Dockerfile

Production-style: 22 lines, no inline rationale comments. Rationale lives in this document, in commit messages, and in the recorded narration. The Dockerfile itself is just the specification.

```dockerfile
# syntax=docker/dockerfile:1.7
FROM python:3.11.10-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tini \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system --gid 1000 app \
    && useradd  --system --uid 1000 --gid app --create-home --home-dir /home/app app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN chown -R app:app /app
USER app
ENV APP_PORT=5000
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/api/health').read()" \
        || exit 1
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "app.py"]
```

**Layer caching verified:** three builds in succession.

| Build | Trigger | Time | Cache state |
|---|---|---|---|
| 1st | Cold cache | 29.2s | Nothing cached, full build |
| 2nd | No file changes | 1.5s | All 8 layers `CACHED` |
| 3rd | Edited `app.py` | 2.1s | Layers 1-6 cached (including pip install), layers 7-8 (COPY + chown) re-ran |

**19× speedup from layer caching.** This is the docker-005 demonstration in concrete numbers.

**Container verification:** the image was started with `--network host` (debugging shortcut) and `-e DB_HOST=localhost`, then curled. `/api/health` returned `{"status":"ok"}`, `/api/data` returned three messages, the HEALTHCHECK reported `(healthy)` after ~10 seconds.

### Step 6 — Frontend code

Two files written:

- **`index.html`** — A minimal page that calls `fetch('/api/data')` and renders the result. Note the *relative* URL — the browser hits whatever host served the page. CORS goes away because nginx serves both the page and the API on the same origin.
- **`nginx.conf`** — Worker config, MIME types, two `location` blocks, an upstream definition, healthcheck endpoint, and crucially dual-stack listen directives (`listen 8080;` AND `listen [::]:8080;`).

### Step 7 — Frontend Dockerfile (multi-stage)

```dockerfile
# syntax=docker/dockerfile:1.7

FROM alpine:3.20 AS builder
WORKDIR /build
RUN apk add --no-cache gzip
COPY index.html .
RUN gzip -k -9 index.html

FROM nginx:1.27-alpine AS runtime
RUN apk add --no-cache tini \
    && addgroup -S app -g 1000 \
    && adduser  -S app -G app -u 1000 \
    && mkdir -p /var/log/nginx /var/cache/nginx /tmp \
    && chown -R app:app /var/log/nginx /var/cache/nginx /usr/share/nginx/html /tmp

COPY --from=builder /build/index.html    /usr/share/nginx/html/index.html
COPY --from=builder /build/index.html.gz /usr/share/nginx/html/index.html.gz
COPY nginx.conf /etc/nginx/nginx.conf

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --quiet --spider http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]
```

**Real production-grade rebuild after a false start.** The first attempt at this Dockerfile used the builder stage to validate the nginx config with `nginx -t`. That failed at build time because `nginx -t` tries to resolve upstream hostnames (`backend:5000`) at config-test time, and `backend` doesn't exist outside the compose network. **The lesson — covered prominently in the recording — is that build-time validators cannot probe runtime state.** The fixed version uses the builder stage for something genuinely build-appropriate: pre-compressing the HTML with `gzip -k -9`. The `gzip` tool itself stays in the builder and never makes it into the runtime image. nginx in the runtime image serves the pre-compressed `.gz` file when `gzip_static on` is set in the config.

**Second debugging moment caught on camera:** the healthcheck initially reported `(unhealthy)` despite `curl` from the Pi working fine. Diagnosis: alpine's busybox `wget` resolves `localhost` to IPv6 (`::1`) first and doesn't fall back to IPv4. nginx was only listening on IPv4. Fix: add `listen [::]:8080;` to the nginx config so the server is dual-stack. **Real platform-engineering content** — the kind of small, infuriating bug that bites people in production.

**Image size comparison** (docker-004):

| Image | Size |
|---|---|
| `multi-tier-frontend:dev` | 49.9 MB |
| `multi-tier-backend:dev` | 192 MB |

Frontend ~4× smaller than backend. The backend ships a full Python interpreter plus compiled C extensions for psycopg2. The frontend ships nginx (a static C binary) on alpine. **Same architecture, very different runtime, very different size.**

### Step 8 — docker-compose.yml + .env pattern

The file is at the project root of `solution/`, not inside any tier subdirectory, because compose's job is to describe **the whole system**, not any one tier.

```yaml
services:
  database:
    image: postgres:15
    container_name: multi-tier-postgres
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./docker/database/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

  backend:
    build:
      context: ./docker/backend
      dockerfile: Dockerfile
    image: multi-tier-backend:dev
    container_name: multi-tier-backend
    environment:
      DB_HOST: database
      DB_PORT: "5432"
      DB_NAME: postgres
      DB_USER: postgres
      DB_PASSWORD: ${DB_PASSWORD}
      APP_PORT: "5000"
    depends_on:
      database:
        condition: service_healthy
    restart: unless-stopped

  frontend:
    build:
      context: ./docker/frontend
      dockerfile: Dockerfile
    image: multi-tier-frontend:dev
    container_name: multi-tier-frontend
    ports:
      - "8080:8080"
    depends_on:
      backend:
        condition: service_started
    restart: unless-stopped

volumes:
  postgres-data:
```

**The secrets discipline:** the file uses `${POSTGRES_PASSWORD}` and `${DB_PASSWORD}` references — never literal values. The actual values live in `solution/.env` which is gitignored. A companion `solution/.env.example` is committed as the contract:

```
# Copy this file to .env and fill in your own values.
# .env is gitignored and never committed.

POSTGRES_PASSWORD=changeme
DB_PASSWORD=changeme
```

The `.gitignore` has a negation pattern (`!.env.example`) to keep the template in git while keeping the real `.env` out.

**The stack came up in 5.9 seconds:**

```
✔ Image multi-tier-frontend:dev Built          2.3s
✔ Image multi-tier-backend:dev  Built          2.3s
✔ Container multi-tier-postgres Healthy        5.9s
✔ Container multi-tier-backend  Created        0.1s
✔ Container multi-tier-frontend Created        0.1s
```

Note the ordering — postgres reported `Healthy` (via the `pg_isready` healthcheck) before the backend was even *created*. Compose enforced the `depends_on: service_healthy` contract automatically.

**End-to-end proof through compose:**

```bash
curl -s http://localhost:8080/healthz       # → "ok"
curl -s http://localhost:8080/              # → first lines of index.html
curl -s http://localhost:8080/api/data      # → JSON, count: 3, three messages
```

All three curls returned the same answers as Step 7's manual orchestration — but with **no `--add-host`, no `--network host`, no manual port publishing on the backend or database.**

**Service-name DNS proven directly:**

```bash
docker exec multi-tier-backend python -c \
  "import socket; print(socket.gethostbyname('database'))"
# → database resolves to: 172.18.0.2

docker exec multi-tier-frontend getent hosts backend
# → 172.18.0.3      backend
```

The hostnames `database` and `backend` only exist inside the compose network. Compose's embedded DNS server at `127.0.0.11` resolves them automatically.

**Volume persistence proven:**

```bash
docker compose down                       # Containers gone, volume kept
docker compose up -d database             # Bring just the DB back
docker exec multi-tier-postgres \
  psql -U postgres -c "SELECT count(*) FROM messages;"
# → 3
```

Brand-new container, mounted the same `solution_postgres-data` named volume, found the existing data. `init.sql` was NOT re-run (it only runs on a clean data directory). **Container disposable. Data permanent.**

---

## Command Breakdown Tables

### `docker compose up -d --build`

| Flag | Plain English |
|---|---|
| `docker compose` | Compose v2 plugin (note the space, not `docker-compose`) |
| `up` | "Bring services up." Creates network, volumes, containers as needed |
| `-d` | Detached — run in background, return prompt immediately |
| `--build` | Build local images from their Dockerfiles before starting. Without this, compose uses cached images |

### `docker compose down`

Stops all services in the compose project, removes the containers, removes the network. **Does NOT remove named volumes** unless `-v` is added. Volumes hold data — Docker requires explicit opt-in for destruction.

### `docker compose ps`

Compose-aware version of `docker ps`. Shows services by their service name (`frontend` / `backend` / `database`) rather than just container names. Limits the view to the current compose project.

### `docker system prune -a -f`

| Flag | Effect |
|---|---|
| `prune` | Removes stopped containers, unused networks, dangling images, build cache |
| `-a` | Also removes **unused** images (tagged but not used by any container), not just dangling ones |
| `-f` | Skip the "are you sure?" prompt |
| (no `--volumes`) | Volumes are **NOT** touched. Opt-in via separate `docker volume prune` |

### `docker exec multi-tier-postgres psql -U postgres -c "SELECT count(*) FROM messages;"`

| Bit | Plain English |
|---|---|
| `docker exec` | Run a command inside a running container |
| `multi-tier-postgres` | The container name (set via `container_name:` in compose) |
| `psql -U postgres` | The postgres CLI client, connecting as the `postgres` superuser |
| `-c "SELECT ..."` | Run one command and exit (vs dropping into the interactive prompt) |

### Multi-stage Dockerfile pattern

```dockerfile
FROM alpine:3.20 AS builder       # ← Stage 1 — disposable
RUN apk add --no-cache gzip
COPY index.html .
RUN gzip -k -9 index.html

FROM nginx:1.27-alpine AS runtime # ← Stage 2 — the final image
COPY --from=builder /build/index.html.gz /usr/share/nginx/html/
```

The `AS builder` names the stage. The `COPY --from=builder` in stage 2 pulls files from stage 1. Everything in stage 1 that *isn't* copied is discarded. Final image contains: nginx + the gzipped file. **Does not contain:** alpine itself, gzip, the alpine package manager.

### Backend Dockerfile layer ordering (docker-005)

```dockerfile
WORKDIR /app
COPY requirements.txt .              # ← Step A
RUN pip install -r requirements.txt  # ← Step B (slow, cached if A unchanged)
COPY app.py .                        # ← Step C
```

If `app.py` changes but `requirements.txt` doesn't, Docker re-runs step C but reuses the cached output of step B. **`pip install` does not run again.** If we'd copied everything in one `COPY . .` before `pip install`, any code change would invalidate the install layer.

---

## Interview Question Coverage

The following interview questions from the master prep file were covered in this module, with slide decks delivered for each:

| Question ID | Topic | Where it landed | Angle covered |
|---|---|---|---|
| **docker-001** | Container vs VM | Step 2 narrative | Shared kernel model; namespaces + cgroups; when to choose VMs anyway (regulated workloads, strong isolation) |
| **docker-002** | Dockerfile best practices | Step 5 (backend Dockerfile) | Pinned base, slim image, non-root user, layer ordering, single-RUN cleanup, baked-in healthcheck, tini as PID 1 |
| **docker-003** | Multi-stage builds | Step 7 (frontend Dockerfile) | Disposable builder stage, runtime keeps only the output, gzip pre-compression as honest builder work; debugging the false start with `nginx -t` validator |
| **docker-004** | Image optimisation | Step 7 (size comparison) | Base image choice (slim vs alpine vs distroless), pull time / storage / attack surface / bandwidth costs, 4× size difference between frontend and backend |
| **docker-005** | Layers & caching | Step 5 (build sequence demo) | Each instruction creates a layer; cache invalidation cascades; `requirements.txt` before `app.py` for cache reuse; demonstrated with 29s → 1.5s → 2.1s build times |
| **docker-006** | Compose networking | Step 8 (compose up) | Private bridge network; embedded DNS at 127.0.0.11; service-name → IP resolution; proven with `getent hosts backend` returning `172.18.0.3` |
| **docker-007** | Volumes vs bind mounts | Step 8 (compose volumes) | Named volumes Docker-managed and persistent; bind mounts host-controlled and injected; proven with `compose down` + `compose up database` returning the same 3 rows |
| **docker-008** | Compose itself | Step 8 (the whole step) | Declarative spec vs imperative `docker run`; `depends_on` with healthcheck conditions; one file = one deployment |
| **docker-009** | ECR | (Covered in Module 1) | Authentication, lifecycle policies, image mutability — already done in Terraform module |
| **linux-002** | PID 1 and signals | Step 5 narrative (tini) | SIGTERM vs SIGKILL; Python doesn't handle PID 1 correctly; tini as 24KB init that forwards signals and reaps zombies |

**Ten interview-question slide decks delivered**, all in `projects/project-001-build-multi-tier-app/interview-slides/`.

Additional explainer decks (not Q-based):

- `module-2-context.pptx` — opening framing on the app-team / platform-team contract
- `module-2-step-5-recap.pptx` — the three-tier explainer
- `module-2-step-5-swimlane.pptx` — swimlane view of the manual-wiring world

Architecture diagrams (Mermaid, plain text, GitHub-renderable):

- `architecture-step5.md` — the manual-wiring world (Step 5)
- `sequence-step5.md` — request flow through manual wiring
- `architecture-step6.md` — the compose world (Step 6)
- `sequence-step6.md` — request flow through compose

---

## Project vs Real Life

The following twenty-one notes flag where decisions in this module diverge from how the same problem would be solved in a real production environment.

| # | What we did | What a real production environment does |
|---|---|---|
| 1 | Manual `docker system prune` to free disk | Image GC policies on the host, lifecycle rules on the registry, log rotation on disk, K8s eviction thresholds |
| 2 | Plain containers with shared kernel | Where regulated workloads or strong isolation matter, use Kata Containers / Firecracker (container ergonomics, VM-grade isolation) |
| 3 | App code, requirements, tests written by the platform engineer | App-team owns this. Platform engineer's role starts at the Dockerfile, after PR review against the contract |
| 4 | `init.sql` for schema bootstrap | Schema changes go through migration tools (Flyway, Alembic, Liquibase) with explicit version tracking. `init.sql` is dev/local only |
| 5 | App-team artefacts written for portfolio | In real industry, app code arrives in PRs. Platform engineer reviews against the five contract points (configurable port, /health endpoint, env-var config, stdout logging, declared deps), then adds Dockerfile + compose entry |
| 6 | Schema content written by platform | Schema content is app-team territory. Only the *mechanism* of loading it (mount path, compose wiring) is platform |
| 7 | Per-request DB connections in Flask | Connection pooling (SQLAlchemy + pool, or PgBouncer) for any non-trivial app |
| 8 | One `requirements.txt` (prod + test deps mixed) | `requirements.txt` + `requirements-dev.txt` split, dev deps not shipped to production image |
| 9 | `psycopg2-binary` for convenience | Compile `psycopg2` from source in production so you control the libpq version and security patching cycle |
| 10 | Flask dev server | Production Flask runs under gunicorn or uwsgi behind nginx. The "do not use in production" warning is real |
| 11 | Plaintext DB password in env vars and `.env` file | Production uses Docker secrets, K8s Secrets, HashiCorp Vault, or AWS Secrets Manager. Never env vars carrying secret material |
| 12 | Pinned direct deps, unpinned transitive | Use `pip-tools` (`pip-compile`) to generate a fully-pinned `requirements.lock.txt` with every transitive dep at an exact version. Install from the lock file |
| 13 | Production Dockerfile with no inline rationale comments | Rationale lives in ADRs, commit messages, runbooks, and team docs. Inline comments are a training artefact; they drift and get skimmed |
| 14 | Containers held data across `stop`/`start` | Production *must* use named volumes (or PersistentVolumes in K8s) for any data that should outlive the container. `docker rm` would have been catastrophic |
| 15 | `--network host` for backend (debugging shortcut) | Production uses bridge / overlay networks with service discovery by name. Host networking removes isolation and is rare in production |
| 16 | `DB_PASSWORD` as a CLI flag during manual runs | Never. Shell history, `ps` output, audit logs all leak it. Use secrets management |
| 17 | nginx config validation attempted in Dockerfile builder | Build-time validators cannot probe runtime state (upstream DNS resolution). Use compose / integration tests, not Dockerfile builds, for config that depends on the network |
| 18 | nginx IPv4-only `listen` directive initially | Production nginx is dual-stack from day one. Or healthchecks should pin to `127.0.0.1` explicitly. busybox `wget` does not gracefully fall back IPv6 → IPv4 |
| 19 | Hardcoded secrets in YAML (the bug you caught) | Never. `.env` pattern for local dev, K8s Secrets / Vault / Secrets Manager for production |
| 20 | `.env.example` as the contract template | Standard practice across modern repos. Documents what variables exist without leaking values |
| 21 | Docker Compose as the orchestrator | Compose is dev/test orchestration. Production = Kubernetes (multi-node) or ECS / Cloud Run (managed). Compose doesn't scale beyond one host |

---

## Key Concepts Learned

**The platform-engineer contract.** Application teams own *what the code does*. Platform engineers own *where it runs and how it gets there*. The boundary between the two is the container image. The contract is five things: configurable port, `/health` endpoint, env-var config, stdout logging, declared dependency manifest.

**Build in dependency order.** Database → backend → frontend. Each tier proven in isolation before the next consumed it. Removes variables one at a time from the debugging surface.

**Layer caching is structural, not incidental.** Where you put your `COPY` instructions in a Dockerfile determines whether your builds take 29 seconds or 1.5 seconds. Pinned dependencies above slow installs above changing source code.

**Multi-stage builds keep build tools out of runtime images.** The textbook reason is image size. The deeper reason is that build-time tooling is a liability — extra binaries, extra CVEs, extra attack surface. If something only needs to exist during the build, it doesn't belong in the shipped artefact.

**PID 1 is special.** A process running as PID 1 has kernel-mandated responsibilities — signal handling, zombie reaping — that most applications don't implement correctly. Use a tiny init (`tini`, `dumb-init`) to wrap your real process.

**Service names beat IPs.** Compose's embedded DNS makes service names resolve to current container IPs. The IPs change. The names don't. This pattern scales directly to Kubernetes (where `Service` resources do exactly the same job).

**Build-time validators cannot probe runtime state.** `nginx -t` looks like a great builder-stage check until you discover it tries to resolve upstream hostnames at config-test time. Build-time should check things that don't depend on the system being up — syntax, file existence, static asset minification. Anything network-dependent goes to integration tests.

**Containers are disposable. Data is not.** Named volumes are the mechanism that makes this real. `docker rm` removes the container, the volume persists. The same mental model applies to Kubernetes PersistentVolumes.

**One file = one deployment.** `docker-compose.yml` is the deployment specification for this stack. Anyone clones the repo, runs `docker compose up`, and gets the same three containers with the same network and the same volume. **The system IS the file.** This is what infrastructure-as-code delivers in practice.

**Secrets never touch git.** `.env` pattern for dev, secret managers for production. `.env.example` is the contract.

---

## Cleanup

> **PROMINENT:** every module that touches the Pi or AWS includes a cleanup section. This module's cleanup is Pi-side only — no AWS resources were created.

### After running the lab

To tear down the running stack and free resources:

```bash
cd ~/cloud-engineer-labs/projects/project-001-build-multi-tier-app/solution
docker compose down
```

**This keeps the named volume.** Postgres data survives. If you re-run `docker compose up -d` later, the same data comes back. This is usually what you want.

### To wipe everything including the data

```bash
docker compose down -v
```

The `-v` flag tells compose to remove named volumes too. Use this when you want to start completely fresh — for example, to test that `init.sql` re-seeds correctly.

### To clean built images as well

```bash
docker compose down -v
docker rmi multi-tier-backend:dev multi-tier-frontend:dev
docker rmi postgres:15  # optional — kept by default since it's an upstream image
```

### To clear orphan volumes from earlier experimentation

```bash
docker volume prune -f
```

This removes any unnamed/dangling volume not currently mounted by a container. Safe to run anytime.

### Future-cleanup reminder

If this lab is being re-run from a clean slate later, the standard sequence at the start of the recording is:

```bash
docker system prune -a -f          # containers, images, networks, build cache
docker volume prune -f             # orphan volumes
```

This reclaims everything not currently in use. It's idempotent.

---

## What's next (Module 3)

Module 3 takes the three images we just built and deploys them to a Kubernetes cluster (K3s on the Pi). The mental models from this module — service names resolving via DNS, healthchecks gating dependency startup, named volumes outliving the workload, secrets kept separate from manifests — **all carry over directly.** What compose does for three containers on one host, Kubernetes does for thousands of pods across many nodes. Same patterns, different scale.

Specific Module 3 work: namespace, ConfigMaps for non-secret config, Secrets for the postgres password (replacing `.env`), PersistentVolumeClaim (replacing the named volume), Deployments for stateless tiers, StatefulSet for postgres, Services for internal DNS, Ingress for external access, NetworkPolicy for the security model `--network host` was hiding.

---

## File index

Everything produced in this module, with the path each artefact lives at:

| Path | Purpose |
|---|---|
| `solution/docker-compose.yml` | The deployment spec |
| `solution/.env.example` | Secrets contract (committed) |
| `solution/.env` | Actual secrets (gitignored — never committed) |
| `solution/docker/database/init.sql` | Schema + seed data |
| `solution/docker/backend/app.py` | Flask app |
| `solution/docker/backend/requirements.txt` | Python deps |
| `solution/docker/backend/Dockerfile` | Backend image spec |
| `solution/docker/backend/.dockerignore` | Build context hygiene |
| `solution/docker/frontend/index.html` | Static page |
| `solution/docker/frontend/nginx.conf` | Web server + reverse proxy config |
| `solution/docker/frontend/Dockerfile` | Frontend image spec (multi-stage) |
| `solution/docker/frontend/.dockerignore` | Build context hygiene |
| `solution/tests/backend/test_health.py` | One pytest case |
| `interview-slides/docker-001-container-vs-vm.pptx` | Interview deck |
| `interview-slides/docker-002-dockerfile-best-practices.pptx` | Interview deck |
| `interview-slides/docker-003-multi-stage-builds.pptx` | Interview deck |
| `interview-slides/docker-004-image-optimisation.pptx` | Interview deck |
| `interview-slides/docker-005-layers-and-caching.pptx` | Interview deck |
| `interview-slides/docker-006-compose-networking.pptx` | Interview deck |
| `interview-slides/docker-007-volumes-vs-bind-mounts.pptx` | Interview deck |
| `interview-slides/docker-008-compose.pptx` | Interview deck |
| `interview-slides/linux-002-pid1-signals.pptx` | Interview deck |
| `interview-slides/module-2-context.pptx` | Opening framing |
| `interview-slides/module-2-step-5-recap.pptx` | Three-tier explainer |
| `interview-slides/module-2-step-5-swimlane.pptx` | Swimlane view |
| `docs/architecture-step5.md` | Mermaid: manual-wiring architecture |
| `docs/sequence-step5.md` | Mermaid: manual-wiring request flow |
| `docs/architecture-step6.md` | Mermaid: compose architecture |
| `docs/sequence-step6.md` | Mermaid: compose request flow |
| `SOLUTION-MODULE-02-DOCKER.md` | This document |

---

*End of Module 2.*
