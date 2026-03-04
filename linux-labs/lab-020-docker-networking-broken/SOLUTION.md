# Lab 020 — Containers Can't Talk: Solution Walkthrough

---

## TLDR — What's Actually Going On (Plain English)

Imagine two workers in the same office building, but they've been put on completely different internal phone systems. They can both make calls — but they can't call *each other* because they're not on the same system.

That's exactly what's happened here. You have two Docker containers — one pretending to be a frontend website, one pretending to be a backend API — but whoever set them up accidentally put each one on its own private Docker network. Docker networks are completely isolated from each other, so the containers can't see each other at all. Not even by name.

**The fix is three commands:**

1. Create a new shared network: `docker network create app-net`
2. Add the backend to it: `docker network connect app-net backend-api`
3. Add the frontend to it: `docker network connect app-net frontend-web`

No containers need to be stopped or restarted. They just gain a new way to talk to each other.

---

## Important: How This Lab Is Structured

This lab has two levels, which can be confusing at first:

| Where you are | Prompt looks like | What you do here |
|---|---|---|
| Your Raspberry Pi | `engsnayl@pi:~$` | Start, validate, and stop the lab |
| Lab container | `root@<hex>:/#` | Run Docker commands to fix the broken setup |

When you `docker exec` into the lab container, you're essentially sitting at a workstation that has Docker installed. The two broken containers — `frontend-web` and `backend-api` — are running separately, and you fix them from the lab container.

---

## Thought Process: How to Debug Container Networking

When two containers can't communicate, work through this order:

1. **What's running?** — Check containers exist and are healthy
2. **What does the service do?** — Find out which port to connect to
3. **What error do you get?** — Try the connection and read the failure message
4. **Where are the containers?** — Check which networks they're on
5. **Fix and verify** — Add them to a shared network, then test again

---

## Step-by-Step Solution

### Step 1: Enter the Lab Container

```
📍 Run on your Pi
```

```bash
docker exec -it lab020-docker-networking-broken bash
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker exec` | Run a command inside an already-running container |
| `-it` | Two flags combined: `-i` keeps stdin open (interactive), `-t` allocates a terminal so it feels like a normal shell session |
| `lab020-docker-networking-broken` | The name of the lab container to enter |
| `bash` | The command to run inside it — opens a Bash shell |

From here, all commands run **inside the lab container** unless stated otherwise.

---

### Step 2: See What Containers Are Running

```bash
docker ps
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker ps` | Lists all currently running containers (ps = "process status") |

**What you'll see:** Two containers — `backend-api` and `frontend-web` — both showing status "Up". The containers themselves are fine; the problem is between them.

---

### Step 3: Find Out What Port the Backend Uses

First, check the logs:

```bash
docker logs backend-api
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker logs` | Fetches the stdout/stderr output of a container |
| `backend-api` | The container name to inspect |

**What you'll see:** Nothing. This is because Python buffers its output by default inside containers — the startup message was printed but got stuck in a buffer before it could appear. This is a common Docker gotcha with Python apps.

Since logs didn't help, check the container's configuration directly:

```bash
docker inspect backend-api | grep -A 5 -i cmd
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker inspect backend-api` | Dumps the full configuration of the container as JSON — networks, mounts, environment variables, the command it runs, everything |
| `\|` | Pipe — takes the output of the left command and feeds it as input to the right command |
| `grep -A 5 -i cmd` | Find the line containing "cmd" (case-insensitive due to `-i`) and show the **5 lines after it** (`-A` = "after") — needed because the value spans multiple lines in JSON |

**What you'll see:**
```
"Cmd": [
    "python3",
    "-c",
    "\nfrom http.server...HTTPServer(('0.0.0.0', 3000), H).serve_forever()\n"
],
```

You can see `3000` in there — the backend is listening on port 3000.

> **Gotcha — why not just `grep -i cmd`?** Without `-A`, grep only returns the matching line itself (`"Cmd": [`), not the lines below it where the actual content lives. JSON values that span multiple lines always need `-A <n>` to be readable. Combining `-A` and `-i` into `grep -A 5 -i cmd` is the cleaner pattern — one flag for lines after, one for case-insensitivity.

> **Alternative:** Just run `docker inspect backend-api` on its own and scroll to the `"Args"` section near the top — it shows the same port information in a slightly cleaner format.

> **Why not use `ss` or `netstat`?** The backend container was built from `python:3.11-slim` — a minimal image with almost no tools installed. Those commands don't exist inside it. `docker inspect` works from outside the container, so it's always available regardless of what's inside.

---

### Step 4: Try to Reach the Backend from the Frontend

```bash
docker exec frontend-web curl http://backend-api:3000
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker exec frontend-web` | Run a command inside the `frontend-web` container |
| `curl` | A command-line tool for making HTTP requests |
| `http://backend-api:3000` | The URL to request — `backend-api` is the container name (Docker should resolve this to an IP address), port `3000` is where the backend listens |

> **Don't use `curl -s` when debugging.** The `-s` flag means "silent" — it hides error messages. Those messages are exactly what you need right now. Save `-s` for scripts where you don't want noise.

**What you'll see:**
```
curl: (6) Could not resolve host: backend-api
```

Error code 6 means DNS failure — the frontend has no idea a container called `backend-api` even exists. It's not a timeout, not a refused connection — it's that the name doesn't resolve at all. That points directly to a network isolation problem.

---

### Step 5: List All Docker Networks

```bash
docker network ls
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker network ls` | Lists all Docker networks on the host |

**What you'll see:**
```
NETWORK ID     NAME           DRIVER    SCOPE
abc123def456   bridge         bridge    local
789012ghi345   backend-net    bridge    local
456789jkl012   frontend-net   bridge    local
```

Two suspicious custom networks: `backend-net` and `frontend-net`. The names suggest each container was put on its own dedicated network — which would explain why they can't see each other.

---

### Step 6: Confirm Which Network Each Container Is On

```bash
docker inspect backend-api | grep -A 50 -i networks
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker inspect backend-api` | Full JSON config dump of the backend container |
| `grep -A 50 -i networks` | Find the line containing "networks" (case-insensitive due to `-i`) and show the next 50 lines — enough to see all network entries including name and IP address |

**What you'll see:**
```
"Networks": {
    "backend-net": {
        ...
        "IPAddress": "172.19.0.2",
```

Now check the frontend:

```bash
docker inspect frontend-web | grep -A 50 -i networks
```

**What you'll see:**
```
"Networks": {
    "frontend-net": {
        ...
        "IPAddress": "172.20.0.2",
```

There's the problem confirmed. The backend is on `172.19.x.x` via `backend-net`. The frontend is on `172.20.x.x` via `frontend-net`. Completely separate networks — no traffic can flow between them.

---

### Step 7: Understand Why This Matters

Docker networks are like separate, isolated subnets. Containers on the **same** custom bridge network can:
- Reach each other by IP address
- Resolve each other's container names via Docker's built-in DNS

Containers on **different** networks have no connectivity whatsoever — no DNS, no routing, nothing. It's as if they're on completely different physical networks.

> **Key gotcha:** Docker's built-in DNS (container name resolution) only works on **custom** bridge networks — ones you create with `docker network create`. The default `bridge` network does NOT support DNS. Containers on the default bridge can only reach each other by IP address, which is fragile. Always create a custom network.

---

### Step 8: Create a Shared Network and Connect Both Containers

```bash
docker network create app-net
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker network create` | Creates a new Docker network |
| `app-net` | The name you're giving the network — you can choose any name |

By default this creates a **bridge** network, which is what you want for containers on the same host.

Now connect both containers to it — **without stopping them:**

```bash
docker network connect app-net backend-api
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `docker network connect` | Adds a running container to a network |
| `app-net` | The network to connect to |
| `backend-api` | The container to connect |

```bash
docker network connect app-net frontend-web
```

Same pattern — adds the frontend to `app-net`.

The containers remain on their original networks too. They now have **two** network connections each. They only need one network in common to be able to reach each other.

---

### Step 9: Verify the Network Configuration Changed

```bash
docker inspect backend-api | grep -A 50 -i networks
```

**What you'll see:** Two network entries — `backend-net` and `app-net`. The container is now on both networks simultaneously. Check `frontend-web` too and you'll see `frontend-net` and `app-net`.

---

### Step 10: Test the Connection

```bash
docker exec frontend-web curl http://backend-api:3000
```

**What you'll see:**
```json
{"status": "healthy", "service": "backend-api"}
```

Docker's DNS on the shared `app-net` network now resolves `backend-api` to its IP address on that network, and the HTTP request goes through successfully.

---

### Step 11: Validate

```
📍 Run on your Pi
```

```bash
lab validate 020
```

All checks should pass.

---

## Summary of What Was Broken

| Issue | What was wrong | How you found it |
|---|---|---|
| Network isolation | `frontend-web` on `frontend-net`, `backend-api` on `backend-net` | `docker inspect` + `grep -A 15 "Networks"` showed different networks |
| DNS failure | Container name lookup failed completely | `curl` returned "Could not resolve host: backend-api" |

---

## Real World Comparison

**This vs. Docker Compose:** In real projects, most multi-container apps use Docker Compose, which automatically creates a shared network for all services in the compose file. You rarely hit this problem with Compose because it handles networking for you. Understanding what Compose does under the hood is exactly what this lab teaches.

**This vs. Kubernetes:** Kubernetes uses Services and CoreDNS to do the same thing — give containers stable names they can reach each other by. The concept is identical, the tooling is different.

**Network isolation as a feature:** Docker's network isolation isn't a bug — it's a deliberate security feature. In production, you might intentionally put a database on a separate network from public-facing containers. What happened here was *accidental* isolation. Knowing how to diagnose and fix it is the skill.

**`docker network connect` without restart:** This is a genuinely useful production technique. You can temporarily add a container to a network for debugging, run your tests, then `docker network disconnect` to remove it — all without any downtime.

**Python stdout buffering:** You'll keep hitting this with Python containers. The production fix is to add `ENV PYTHONUNBUFFERED=1` to the Dockerfile, or run Python with the `-u` flag. Then `docker logs` works as expected.

---

## Alternative Fixes

**Option A — Connect frontend directly to the backend's existing network:**
```bash
docker network connect backend-net frontend-web
```
Works, but leaves both containers on a network called "backend-net" which is misleading.

**Option B — Recreate containers on a shared network:**
```bash
docker rm -f frontend-web backend-api
docker network create app-net
# Re-run both containers with --network app-net
```
Works, but causes downtime while containers are recreated.

**Option C — Use IP addresses directly:**
You could find the backend's IP with `docker inspect` and curl that IP instead of the hostname. This is fragile — IPs can change when containers restart. Always use DNS names where possible.

---

## Common Mistakes

- **Connecting to the default `bridge` network:** Containers on the default bridge can reach each other by IP but NOT by name. Always use a custom network for DNS to work.
- **Using `localhost` to reach another container:** Each container's `localhost` refers only to itself. `curl http://localhost:3000` from the frontend will never reach the backend.
- **Thinking you need to restart containers:** `docker network connect` works on running containers. No stop, no remove, no recreate needed.
- **Hardcoding IP addresses:** Container IPs change when containers restart. Use container names — they stay stable as long as the container exists.
- **Using `curl -s` when debugging:** Silent mode hides error messages. Only use `-s` in scripts where you don't want output noise.
- **Confusing the lab container with the target containers:** The lab container is your workstation. `frontend-web` and `backend-api` are the containers you're fixing.

---

## Key Commands Reference

| Command | What it does |
|---|---|
| `docker ps` | List running containers |
| `docker logs <container>` | View container stdout/stderr output |
| `docker inspect <container>` | Dump full container configuration as JSON |
| `docker network ls` | List all Docker networks |
| `docker network create <name>` | Create a new custom bridge network |
| `docker network connect <network> <container>` | Add a running container to a network |
| `docker network disconnect <network> <container>` | Remove a container from a network |
| `docker exec <container> <command>` | Run a command inside a running container |
| `grep -A <n> "<term>"` | Find a line matching a term and show `n` lines after it |
