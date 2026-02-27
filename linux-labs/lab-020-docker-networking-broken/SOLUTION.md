# Solution Walkthrough — Lab 020: Containers Can't Talk

## TLDR

You've got two Docker containers (frontend-web and backend-api) that have been set up on two different networks so they can't talk to each other. You need to create a shared network and add them both to it.

That's it. The commands are `docker network create app-net`, then `docker network connect app-net backend-api` and `docker network connect app-net frontend-web`. Done.

The rest of this walkthrough teaches you how to *diagnose* the problem — which is the actual skill you're learning.

---

## The Problem

Two containers — a frontend and a backend API — have been deployed but can't communicate. They were manually placed on separate Docker networks during a migration, so they're completely isolated from each other. Docker's networking model means containers on different networks can't see each other at all — not by IP, not by hostname.

## Important: How This Lab Works

Like lab 019, this is a Docker lab with two levels:

- **Your Pi** (`engsnayl@pi:~$`) — `lab start`, `lab validate`, `lab stop`
- **Lab container** (`root@<hex>:/#`) — your workstation, where you run Docker commands to manage the broken containers

The lab container has the Docker socket mounted so you can manage other containers from inside it. The broken environment is two other containers (frontend-web and backend-api) that were automatically created when the lab started.

## Thought Process

When containers can't communicate, the debugging order is:

1. **See what's running** — What containers exist? What are their names?
2. **Figure out what the service does** — What port is it on? What does it serve?
3. **Try to connect** — What error do you get?
4. **Check the networks** — Are the containers on the same network?
5. **Fix the networking** — Get them onto a shared network
6. **Verify** — Test the connection works

## Step-by-Step Solution

### Step 1: Get into the lab container

```
📍 Run this on your Pi
```

```bash
docker exec -it lab020-docker-networking-broken bash
```

From this point forward, all commands are run inside the lab container unless stated otherwise.

---

### Step 2: See what containers are running

```
📍 Run this inside the lab container
```

```bash
docker ps
```

**What you'll see:** Two containers — `backend-api` and `frontend-web` — both with status "Up". So the containers themselves are fine, they're running. The problem is between them.

---

### Step 3: Figure out what the backend service does

Before trying to connect to anything, we need to know what port the backend is running on. Let's check the logs first:

```bash
docker logs backend-api
```

**What you'll see:** Probably nothing. This is because Python buffers its stdout output inside containers by default — the app printed a startup message but it's stuck in a buffer. This is a common Docker gotcha you'll run into a lot.

So logs didn't help. The next option is to look at what command the container is running:

```bash
docker inspect backend-api | grep -i cmd
```

**What you'll see:**
```
"Cmd": ["python3", "-c", "\nfrom http.server import HTTPServer...HTTPServer(('0.0.0.0', 3000), H).serve_forever()\n"],
```

It's a bit messy, but you can see `3000` in there — that's the port the backend is listening on. It's running a Python HTTP server on port 3000.

> **Why not use `ss` or `netstat`?** The backend container is built from `python:3.11-slim` which is a minimal image — it doesn't have `ss`, `netstat`, or most other networking tools installed. `docker inspect` works on any container because it runs on the Docker host, not inside the container.

---

### Step 4: Try to reach the backend from the frontend

```bash
docker exec frontend-web curl http://backend-api:3000
```

**What this does:** Runs `curl` inside the frontend-web container, trying to reach the backend-api by its container name on port 3000.

> **Important:** Don't use `curl -s` when troubleshooting. The `-s` (silent) flag hides error messages, which is exactly what you need to see right now. Use `-s` in scripts, not when debugging.

**What you'll see:**
```
curl: (6) Could not resolve host: backend-api
```

The frontend can't even *resolve the name* `backend-api`. It's not a timeout or a refused connection — it's a DNS failure. The frontend has no idea that a container called `backend-api` exists. This is the clue that it's a network isolation issue.

---

### Step 5: List the Docker networks

```bash
docker network ls
```

**What this does:** Shows all Docker networks on the system.

**What you'll see:**
```
NETWORK ID     NAME           DRIVER    SCOPE
abc123def456   bridge         bridge    local
789012ghi345   backend-net    bridge    local
456789jkl012   frontend-net   bridge    local
...
```

There are two custom networks: `backend-net` and `frontend-net`. The names are suspicious — it looks like someone put each container on its own dedicated network.

---

### Step 6: Check which network each container is on

```bash
docker inspect backend-api | grep -A 15 "Networks"
```

**What this does:** `docker inspect` dumps all the container's configuration as JSON. Piping through `grep -A 15 "Networks"` finds the "Networks" section and shows the next 15 lines, which includes the network name and IP address.

**What you'll see:**
```
            "Networks": {
                "backend-net": {
                    "IPAMConfig": null,
                    "Links": null,
                    "Aliases": null,
                    ...
                    "IPAddress": "172.19.0.2",
```

Now check the frontend:

```bash
docker inspect frontend-web | grep -A 15 "Networks"
```

**What you'll see:**
```
            "Networks": {
                "frontend-net": {
                    ...
                    "IPAddress": "172.20.0.2",
```

There's the problem: backend-api is on `backend-net`, frontend-web is on `frontend-net`. They're on completely separate networks with different IP ranges (172.19.x.x vs 172.20.x.x). They can't reach each other at all.

---

### Step 7: Understand why this matters

Docker networks are like separate VLANs or subnets. Containers on the same custom bridge network can:
- Reach each other by IP address
- Resolve each other's container names via Docker's built-in DNS (this is the key feature)

Containers on *different* networks have no connectivity at all — no DNS, no IP routing, nothing. It's as if they're on completely different physical networks.

> **Important:** Docker's built-in DNS only works on **custom** bridge networks (ones you create with `docker network create`). The default `bridge` network does NOT support DNS resolution — containers on it can only reach each other by IP address. This is a common gotcha.

---

### Step 8: Create a shared network and connect both containers

```bash
docker network create app-net
```

**What this does:** Creates a new custom bridge network called `app-net`. You can name it anything you like.

Now connect both containers to it:

```bash
docker network connect app-net backend-api
docker network connect app-net frontend-web
```

**What this does:** `docker network connect` adds a container to an additional network **without stopping it**. This is important — the containers stay running the whole time. They're now on their original networks *and* on app-net. They just need one network in common to communicate.

---

### Step 9: Verify the network configuration changed

```bash
docker inspect backend-api | grep -A 15 "Networks"
```

**What you'll see:** Now there are two network entries instead of one — `backend-net` and `app-net`. The container is on both networks simultaneously. Check frontend-web too and you'll see the same — it's now on `frontend-net` and `app-net`.

---

### Step 10: Test the connection

```bash
docker exec frontend-web curl http://backend-api:3000
```

**What you'll see:**
```
{"status": "healthy", "service": "backend-api"}
```

The frontend can now reach the backend by name. Docker's DNS on the shared `app-net` network resolves `backend-api` to its IP address on that network, and the HTTP request gets through.

---

### Step 11: Validate

```
📍 Run this on your Pi
```

```bash
lab validate 020
```

All checks should pass.

## Summary of What Was Broken

| Issue | What was wrong | How you found it |
|-------|---------------|-----------------|
| Network isolation | frontend-web on `frontend-net`, backend-api on `backend-net` | `docker inspect` + grep showed different networks |
| No DNS resolution | Container name lookup failed | `curl` returned "Could not resolve host" |

## Docker Lab vs Real Life

**docker network create/connect:** These are real Docker commands you'd use in production for standalone containers. In practice though, most multi-container apps use Docker Compose, which automatically creates a shared network for all services in the compose file — you rarely have this problem with Compose.

**Docker DNS:** The built-in DNS that lets containers find each other by name is exactly how Docker Compose networking works behind the scenes. In Kubernetes, a similar mechanism exists through Services and kube-dns/CoreDNS.

**Network isolation:** Docker's network isolation is actually a security feature. In production, you might deliberately keep databases on a separate network from public-facing containers. The problem here was accidental isolation, but intentional isolation is good practice.

**docker network connect without restart:** This is a genuinely useful production trick. You can add a container to a network for debugging, run your tests, then `docker network disconnect` to remove it — all without downtime.

**Python stdout buffering:** This will keep coming up with Python containers. The fix in production is to add `ENV PYTHONUNBUFFERED=1` to your Dockerfile, or run Python with the `-u` flag. Then `docker logs` works as expected.

## Key Concepts Learned

- **`docker network ls`** shows all Docker networks
- **`docker network create <n>`** creates a custom bridge network
- **`docker network connect <network> <container>`** adds a container to a network without stopping it
- **`docker network disconnect <network> <container>`** removes a container from a network
- **`docker inspect <container> | grep -A 15 "Networks"`** shows which networks a container is on
- Containers must be on the **same custom bridge network** to resolve each other's names
- The **default bridge network** does NOT support DNS resolution — only custom networks do
- A container can be on **multiple networks** simultaneously
- Don't use `curl -s` when troubleshooting — the `-s` flag hides error messages
- Minimal Docker images (`*-slim`, `alpine`) often lack basic tools like `ss` and `netstat` — use `docker inspect` instead

## Alternative Fixes

There were other ways to solve this:

**Option A — Connect frontend to backend's network:**
```bash
docker network connect backend-net frontend-web
```
This works but leaves you dependent on a network called "backend-net" which is misleading since both containers are on it.

**Option B — Recreate containers on a shared network:**
```bash
docker rm -f frontend-web backend-api
docker network create app-net
# Then re-run both containers with --network app-net
```
This works but means downtime while you recreate the containers. The `docker network connect` approach has zero downtime.

**Option C — Use container IP addresses directly:**
You could find the backend's IP and curl that instead of the hostname. This is fragile — IPs change when containers restart. Always use DNS names.

## Common Mistakes

- **Forgetting that the default bridge doesn't support DNS:** If you connect both containers to the default `bridge` network, they can reach each other by IP but not by name. Always use a custom network.
- **Trying to use localhost:** `curl http://localhost:3000` from the frontend won't reach the backend. Each container's `localhost` refers to itself only.
- **Thinking you need to restart containers:** `docker network connect` works on running containers. No need to stop, remove, and recreate.
- **Using IP addresses instead of names:** Hardcoding IPs works temporarily but breaks when containers restart and get new IPs. Container names are stable.
- **Using `curl -s` when debugging:** Silent mode hides the error messages that tell you what's actually wrong. Only use `-s` in scripts.
- **Confusing the lab container with the target containers:** The lab container is your workstation. The frontend-web and backend-api are the containers you're fixing. Docker commands you run in the lab container manage those other containers via the mounted socket.
