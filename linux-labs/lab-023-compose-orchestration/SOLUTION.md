# Solution Walkthrough — Compose Orchestration Broken

## The Problem

A full-stack application with three services (Nginx web server, Python API, PostgreSQL database) is defined in a `docker-compose.yml` file, but it can't start due to **four issues**:

1. **`depends_on` references wrong service name** — the `web` service depends on `backend`, but the actual service is called `api`. Docker Compose will error because it can't find a service named `backend`.
2. **Missing volume mount for the API code** — the API service runs `python3 /app/api.py`, but no volume mount copies the code into the container. The `/app/api.py` file doesn't exist inside the container, so Python exits with "file not found."
3. **Wrong database hostname** — the API service has `DB_HOST=database` in its environment, but the database service is called `db` in the Compose file. In Docker Compose, services reach each other by their service name, so the API would try to connect to a non-existent host called `database`.
4. **Missing `POSTGRES_PASSWORD`** — the PostgreSQL image requires the `POSTGRES_PASSWORD` environment variable. Without it, the database container refuses to start and exits with an error message.

## Thought Process

When `docker compose up` fails, an experienced engineer reads the error output from each service:

1. **Start without `-d`** — run `docker compose up` (not `docker compose up -d`) so you can see all output from all services in real time. Errors from different services will be interleaved but color-coded.
2. **Fix the Compose file first** — syntax errors and reference errors (like wrong service names) prevent Compose from even starting. Fix those before looking at runtime issues.
3. **Check each service independently** — does the database start? Does the API have its code? Can services resolve each other by name?
4. **Service names are DNS names** — in Docker Compose, each service name becomes a DNS hostname on the internal network. If you name a service `db`, other services reach it at `db`, not `database`.

## Step-by-Step Solution

### Step 1: Try running it to see all errors

```bash
cd /opt/fullstack-app && docker compose up
```

**What this does:** Starts all services and shows output in the foreground. You'll see errors from multiple services — a reference to non-existent service `backend`, database failing without a password, and the API unable to find its code. Press Ctrl+C to stop after observing the errors.

### Step 2: Look at the current docker-compose.yml

```bash
cat /opt/fullstack-app/docker-compose.yml
```

**What this does:** Shows the broken Compose file. Read through each service definition and identify the four issues.

### Step 3: Fix all four issues in docker-compose.yml

```bash
cat > /opt/fullstack-app/docker-compose.yml << 'EOF'
version: "3.8"
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    depends_on:
      - api
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf

  api:
    image: python:3.11-slim
    command: python3 /app/api.py
    volumes:
      - ./app:/app
    environment:
      - DB_HOST=db
      - DB_PORT=5432

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=apppassword
      - POSTGRES_DB=appdb
EOF
```

**What this does:** Rewrites the Compose file with all four fixes:

1. **`depends_on: api`** (was `backend`) — now references the correct service name. `depends_on` controls startup order — Nginx waits for the API to start before starting itself.
2. **`volumes: - ./app:/app`** added to the `api` service — mounts the local `./app` directory (containing `api.py`) into the container at `/app`. Now the API service can find its code.
3. **`DB_HOST=db`** (was `database`) — matches the actual Compose service name `db`. Other containers can reach the PostgreSQL service at hostname `db`.
4. **`POSTGRES_PASSWORD=apppassword`** added — provides the required password for PostgreSQL. Without this, the official postgres image refuses to start.

### Step 4: Start the fixed stack

```bash
cd /opt/fullstack-app && docker compose up -d
```

**What this does:** Starts all three services in detached mode (`-d`). Docker Compose creates a network, starts `db` first (because `api` might depend on it implicitly), then `api`, then `web` (which depends on `api`).

### Step 5: Check that all services are running

```bash
cd /opt/fullstack-app && docker compose ps
```

**What this does:** Shows the status of all Compose services. All three (web, api, db) should show "Up." If any shows "Exited," check its logs with `docker compose logs <service>`.

### Step 6: Test the full stack

```bash
curl -s http://localhost:80
```

**What this does:** Sends a request to port 80 (Nginx), which proxies it to the API service. You should see `{"status":"ok","db_host":"db"}` — confirming the entire chain works: Nginx → API → (configured for database).

### Step 7: Verify the API directly

```bash
cd /opt/fullstack-app && docker compose exec api curl -s http://localhost:5000
```

**What this does:** Runs curl inside the API container to test it directly (bypassing Nginx). This confirms the API service is healthy on its own.

## Docker Lab vs Real Life

- **Docker Compose in production:** Docker Compose is excellent for development and small deployments. For production at scale, you'd use Kubernetes, Docker Swarm, or ECS. However, many small-to-medium services run perfectly well with Docker Compose + a single server.
- **Database passwords:** In this lab we hardcode the password in the YAML. In production, you'd use Docker secrets, environment files (`.env`), or a secrets manager. Never commit passwords to version control.
- **Health checks:** Production Compose files include `healthcheck` directives and `depends_on` with `condition: service_healthy` to ensure services truly start in the right order (not just that the container is running, but that the application inside is ready).
- **Networking:** Docker Compose automatically creates a bridge network for the project. All services can reach each other by name. You don't need to configure networking manually in most cases.
- **Persistent data:** In production, the database would have a named volume (`db-data:/var/lib/postgresql/data`) so data survives `docker compose down`. Without it, all database data is lost when the container is removed.

## Key Concepts Learned

- **Service names are DNS hostnames** — in Docker Compose, if a service is named `db`, other services reach it at hostname `db`. The `DB_HOST` environment variable must match the service name, not some other name.
- **`depends_on` references must match actual service names** — a typo or wrong name causes Compose to fail before any container starts
- **Volumes are required for code in interpreted languages** — if your container runs `python3 /app/api.py`, the code must actually be inside the container. Either `COPY` it in the Dockerfile or mount it as a volume.
- **PostgreSQL requires `POSTGRES_PASSWORD`** — the official postgres image enforces this. It's not optional. Without it, the container prints an error and exits.
- **Run `docker compose up` (without `-d`) for debugging** — seeing all service output interleaved helps you understand the startup sequence and spot errors quickly

## Common Mistakes

- **Mixing up service names and hostnames** — the service name in the Compose file IS the hostname. If you call it `db`, the hostname is `db`, not `database`, not `postgres`, not `localhost`.
- **Forgetting volume mounts** — the application code needs to get into the container somehow. Either COPY it in a custom Dockerfile or mount it with volumes.
- **Not providing required environment variables** — official Docker images often require specific environment variables. Check the image's Docker Hub page for required variables.
- **Using `depends_on` and expecting the dependency to be "ready"** — `depends_on` only waits for the container to start, not for the application inside to be ready. A database container might be "started" but still initializing. Use healthchecks for true readiness dependencies.
- **Running `docker compose up -d` while debugging** — detached mode hides all output. Use foreground mode (`docker compose up`) while fixing problems so you can see errors in real time.
