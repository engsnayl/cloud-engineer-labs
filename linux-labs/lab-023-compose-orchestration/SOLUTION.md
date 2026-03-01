# Solution Walkthrough — Compose Orchestration Broken

## TLDR

A full-stack app has three services defined in a `docker-compose.yml` file: a web server (Nginx), an API (Python), and a database (PostgreSQL). None of them can start because the Compose file has four mistakes in it. One service name is spelled wrong, the API code isn't mounted into its container, the database hostname is wrong, and the database is missing a required password. You fix all four in the YAML file, bring the stack up, and verify the whole chain works.

---

## The Problem

The app lives at `/opt/fullstack-app` and has three services that are supposed to work together like this:

```
User → Nginx (port 80) → Python API (port 5000) → PostgreSQL database
```

But four bugs in `docker-compose.yml` prevent any of it from working:

1. **Wrong service name in `depends_on`** — the `web` service says it depends on `backend`, but the actual service is called `api`. Compose can't find `backend` so it refuses to start anything.
2. **Missing volume mount for the API code** — the API tries to run `python3 /app/api.py`, but nothing puts that file inside the container. Python says "file not found."
3. **Wrong database hostname** — the API has `DB_HOST=database`, but the database service is called `db`. In Compose, services talk to each other using their service name as a hostname — so it needs to be `db`, not `database`.
4. **Missing `POSTGRES_PASSWORD`** — the official PostgreSQL image requires this variable. Without it, the database container refuses to start.

---

## The Broken Compose File (Before) — Line by Line

```yaml
version: "3.8"                          # Compose file format version (ignored in modern Docker but harmless)
services:                               # Start of service definitions
  web:                                  # First service: the Nginx web server
    image: nginx:alpine                 # Use the official Nginx image (Alpine = small Linux variant)
    ports:
      - "80:80"                         # Map host port 80 → container port 80
    depends_on:
      - backend                         # ❌ BUG 1: No service called "backend" — should be "api"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf   # Mount local nginx.conf into the container

  api:                                  # Second service: the Python API
    image: python:3.11-slim             # Use official Python 3.11 image
    command: python3 /app/api.py        # Run this command when container starts
                                        # ❌ BUG 2: No volume mount — /app/api.py doesn't exist in the container
    environment:
      - DB_HOST=database                # ❌ BUG 3: Wrong hostname — should be "db" to match the service name below
      - DB_PORT=5432                    # Database port (correct)

  db:                                   # Third service: PostgreSQL database
    image: postgres:15-alpine           # Official PostgreSQL 15 image
    environment:
      - POSTGRES_USER=appuser           # Database username
                                        # ❌ BUG 4: Missing POSTGRES_PASSWORD — PostgreSQL won't start without it
      - POSTGRES_DB=appdb               # Database name
```

---

## The Fixed Compose File (After) — Line by Line

```yaml
version: "3.8"                          # Compose file format version
services:
  web:
    image: nginx:alpine                 # Official Nginx image
    ports:
      - "80:80"                         # Host port 80 → container port 80
    depends_on:
      - api                             # ✅ FIX 1: Now references the correct service name "api"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf   # Mount Nginx config into container

  api:
    image: python:3.11-slim             # Official Python image
    command: python3 /app/api.py        # Run the API script
    volumes:
      - ./app:/app                      # ✅ FIX 2: Mount the local ./app folder into /app in the container
    environment:                        #           Now the container can find /app/api.py
      - DB_HOST=db                      # ✅ FIX 3: Hostname matches the service name "db" below
      - DB_PORT=5432                    # Database port

  db:
    image: postgres:15-alpine           # Official PostgreSQL image
    environment:
      - POSTGRES_USER=appuser           # Database username
      - POSTGRES_PASSWORD=apppassword   # ✅ FIX 4: Added the required password
      - POSTGRES_DB=appdb               # Database name
```

---

## Thought Process

When `docker compose up` fails, an experienced engineer reads the error output from each service:

1. **Start without `-d`** — run `docker compose up` (not `docker compose up -d`) so you can see all output from all services in real time. Errors from different services will be interleaved but colour-coded.
2. **Fix the Compose file first** — syntax errors and reference errors (like wrong service names) prevent Compose from even starting. Fix those before looking at runtime issues.
3. **Check each service independently** — does the database start? Does the API have its code? Can services resolve each other by name?
4. **Service names are DNS names** — in Docker Compose, each service name becomes a DNS hostname on the internal network. If you name a service `db`, other services reach it at `db`, not `database`.

---

## Step-by-Step Solution

### Step 1: Find the application

The app files live at `/opt/fullstack-app`. If you didn't know that, you could search for the Compose file:

```bash
find / -name "docker-compose.yml" 2>/dev/null
```

**Command breakdown:**
- `find /` — search starting from the root of the filesystem
- `-name "docker-compose.yml"` — look for files with this exact name
- `2>/dev/null` — hide "permission denied" errors so the output is clean

Then change into the directory:

```bash
cd /opt/fullstack-app
```

### Step 2: Check if Docker Compose is available

```bash
docker compose version
```

**Command breakdown:**
- `docker compose` — the Docker Compose v2 plugin (note: space, not hyphen)
- `version` — just print the version number to confirm it's installed

If this returns "unknown command", install the Compose plugin:

```bash
apt-get update && apt-get install -y docker-compose-v2
```

**Command breakdown:**
- `apt-get update` — refresh the package list so it knows what's available
- `&&` — only run the next command if the first one succeeds
- `apt-get install -y docker-compose-v2` — install the Compose plugin; `-y` means "yes" to all prompts

### Step 3: Try running it to see all errors

```bash
docker compose up
```

**Command breakdown:**
- `docker compose up` — start all services defined in docker-compose.yml
- No `-d` flag = foreground mode, so you see all output from all containers in real time

You'll see the first error immediately — Compose refuses to start because it can't find a service called `backend`. Press `Ctrl+C` to stop.

### Step 4: Read the Compose file

```bash
cat docker-compose.yml
```

**Command breakdown:**
- `cat` — print the contents of a file to the screen
- Read through the file and try to spot all four issues before fixing anything

### Step 5: Fix all four bugs

Open the file in an editor:

```bash
nano docker-compose.yml
```

Or overwrite it in one go:

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

**Command breakdown:**
- `cat >` — redirect input into a file (overwrites the file)
- `<< 'EOF'` — "here document" — everything between this line and `EOF` becomes the file contents
- The single quotes around `EOF` prevent the shell from interpreting any special characters inside

**The four fixes:**
1. `depends_on: api` — was `backend`, now matches the actual service name
2. `volumes: - ./app:/app` — mounts the local `./app` directory into the container at `/app`
3. `DB_HOST=db` — was `database`, now matches the service name `db`
4. `POSTGRES_PASSWORD=apppassword` — added the required password

### Step 6: Start the fixed stack

```bash
docker compose up -d
```

**Command breakdown:**
- `docker compose up` — create and start all services
- `-d` — detached mode, runs in the background so you get your terminal back

### Step 7: Check all services are running

```bash
docker compose ps
```

**Command breakdown:**
- `docker compose ps` — show the status of all services in this Compose project
- All three (web, api, db) should show "Up"
- If any show "Exited", check their logs: `docker compose logs <service>`

### Step 8: Test the full stack

```bash
curl -s http://localhost:80
```

**Command breakdown:**
- `curl` — make an HTTP request from the command line
- `-s` — silent mode, don't show progress bars
- `http://localhost:80` — request port 80 on this machine (which Nginx is listening on)

Expected response: `{"status":"ok","db_host":"db"}`

This confirms the full chain: your request hits Nginx → Nginx proxies to the API → the API reads its DB_HOST config and responds.

### Step 9: Test the API directly

```bash
docker compose exec api curl -s http://localhost:5000
```

**Command breakdown:**
- `docker compose exec` — run a command inside a running container
- `api` — the service name to run the command in
- `curl -s http://localhost:5000` — the command to run (test the API from inside its own container)

Note: This only works if `curl` is installed in the API container. If it's not, you can use Python instead:

```bash
docker compose exec api python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000').read().decode())"
```

### Step 10: Clean up when done

```bash
docker compose down
```

**Command breakdown:**
- `docker compose down` — stop and remove all containers, networks created by `docker compose up`
- Add `-v` to also remove volumes: `docker compose down -v`

---

## Useful Debugging Commands

| Command | What it does |
|---------|-------------|
| `docker compose up` | Start all services in foreground (see all output) |
| `docker compose up -d` | Start all services in background |
| `docker compose down` | Stop and remove everything |
| `docker compose ps` | Show status of all services |
| `docker compose logs api` | Show logs for just the api service |
| `docker compose logs -f` | Follow logs in real time (like tail -f) |
| `docker compose exec api bash` | Get a shell inside the api container |
| `docker compose restart api` | Restart just the api service |

---

## Docker Compose vs Real Life

- **Database passwords:** In this lab we hardcode the password in the YAML file. In production, you'd use Docker secrets, a `.env` file, or a secrets manager like AWS Secrets Manager. Never commit passwords to Git.
- **Health checks:** Production Compose files include `healthcheck` directives so `depends_on` can wait for a service to actually be *ready*, not just *started*. A database container can be "started" but still initialising.
- **Persistent data:** In production, the database would have a named volume (`db-data:/var/lib/postgresql/data`) so your data survives `docker compose down`. Without it, all database data is lost when the container is removed.
- **Networking:** Docker Compose automatically creates a bridge network for the project. All services can reach each other by name. You don't need to configure networking manually.

---

## Key Concepts

- **Service names are DNS hostnames** — if a service is called `db` in the Compose file, other services reach it at hostname `db`. The `DB_HOST` environment variable must match the service name.
- **`depends_on` names must match actual service names** — a typo or wrong name stops everything from starting.
- **Volumes mount code into containers** — if your container runs `python3 /app/api.py`, the code must exist inside the container. Either COPY it in a Dockerfile or mount it as a volume.
- **PostgreSQL requires `POSTGRES_PASSWORD`** — the official image enforces this. No password = no start.
- **Use foreground mode for debugging** — `docker compose up` (without `-d`) lets you see all errors in real time.
