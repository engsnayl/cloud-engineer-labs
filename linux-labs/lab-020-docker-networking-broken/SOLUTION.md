# Solution Walkthrough — Lab 020: Containers Can't Talk

## The Problem

Two containers — a frontend and a backend API — have been deployed but can't communicate. They were manually placed on separate Docker networks during a migration, so they're completely isolated from each other. Docker's networking model means containers on different networks can't see each other at all — not by IP, not by hostname.

## Important: How This Lab Works

Like lab 019, this is a Docker lab with two levels:

- **Your Pi** (`engsnayl@pi:~$`) — `lab start`, `lab validate`, `lab stop`
- **Lab container** (`root@<hex>:/#`) — your workstation, where you run Docker commands to manage the broken containers

The lab container has the Docker socket mounted so you can manage other containers from inside it. The broken environment is two other containers (frontend-web and backend-api) that were automatically created when the lab started.

## Thought Process

When containers can't communicate, the debugging order is:

1. **Confirm the symptom** — Try to connect and see what error you get
2. **Check what networks exist** — What Docker networks are there?
3. **Check which network each container is on** — Are they on the same one?
4. **Understand Docker DNS** — Container name resolution only works on shared custom networks
5. **Connect them to the same network** — Fix the isolation
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

### Step 2: Check what containers are running

```
📍 Run this inside the lab container
```

```bash
docker ps
```

**What you'll see:** Two containers running — `backend-api` and `frontend-web`. Both show status "Up". So the containers themselves are fine — they're running, they just can't talk to each other.

---

### Step 3: Confirm the problem

Let's try to reach the backend from the frontend:

```bash
docker exec frontend-web curl -s http://backend-api:3000
```

**What this does:** Runs `curl` inside the frontend-web container, trying to reach the backend-api by its container name on port 3000.

**What you'll see:**
```
curl: (6) Could not resolve host: backend-api
```

The frontend can't even *resolve the name* `backend-api`. It's not a timeout — it's a DNS failure. The frontend has no idea that a container called `backend-api` exists. This is the clue that it's a network isolation issue.

---

### Step 4: List the Docker networks

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

### Step 5: Check which network each container is on

```bash
docker inspect backend-api --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{"\n"}}{{end}}'
```

**What this does:** `docker inspect` shows detailed information about a container. The `--format` flag uses Go templates to extract just the network information. This shows which network(s) the container is connected to and its IP address on each.

**What you'll see:**
```
backend-net: 172.19.0.2
```

Now check the frontend:

```bash
docker inspect frontend-web --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{"\n"}}{{end}}'
```

**What you'll see:**
```
frontend-net: 172.20.0.2
```

There's the problem: backend-api is on `backend-net`, frontend-web is on `frontend-net`. They're on completely separate networks with different IP ranges (172.19.x.x vs 172.20.x.x). They can't reach each other at all.

---

### Step 6: Understand why this matters

Docker networks are like separate VLANs or subnets. Containers on the same custom bridge network can:
- Reach each other by IP address
- Resolve each other's container names via Docker's built-in DNS (this is the key feature)

Containers on *different* networks have no connectivity at all — no DNS, no IP routing, nothing. It's as if they're on completely different physical networks.

> **Important:** Docker's built-in DNS only works on **custom** bridge networks (ones you create with `docker network create`). The default `bridge` network does NOT support DNS resolution — containers on it can only reach each other by IP address. This is a common gotcha.

---

### Step 7: Create a shared network and connect both containers

There are several ways to fix this. The cleanest is to create a new shared network and connect both containers to it:

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

### Step 8: Verify the network configuration

```bash
docker inspect backend-api --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{"\n"}}{{end}}'
```

**What you'll see:**
```
app-net: 172.21.0.2
backend-net: 172.19.0.2
```

The backend is now on two networks. Do the same for frontend-web — it should also show both its original network and app-net.

---

### Step 9: Test the connection

```bash
docker exec frontend-web curl -s http://backend-api:3000
```

**What you'll see:**
```
{"status": "healthy", "service": "backend-api"}
```

The frontend can now reach the backend by name. Docker's DNS on the shared `app-net` network resolves `backend-api` to its IP address on that network, and the HTTP request gets through.

---

### Step 10: Validate

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
| Network isolation | frontend-web on `frontend-net`, backend-api on `backend-net` | `docker inspect` showed different networks |
| No DNS resolution | Container name lookup failed | `curl` returned "Could not resolve host" |

## The Fix

Created a shared custom bridge network (`app-net`) and connected both containers to it using `docker network connect`. No containers needed to be stopped or recreated.

## Docker Lab vs Real Life

**docker network create/connect:** These are real Docker commands you'd use in production for standalone containers. In practice though, most multi-container apps use Docker Compose, which automatically creates a shared network for all services in the compose file — you rarely have this problem with Compose.

**Docker DNS:** The built-in DNS that lets containers find each other by name is exactly how Docker Compose networking works behind the scenes. In Kubernetes, a similar mechanism exists through Services and kube-dns/CoreDNS.

**Network isolation:** Docker's network isolation is actually a security feature. In production, you might deliberately keep databases on a separate network from public-facing containers. The problem here was accidental isolation, but intentional isolation is good practice.

**docker network connect without restart:** This is a genuinely useful production trick. You can add a container to a network for debugging, run your tests, then `docker network disconnect` to remove it — all without downtime.

## Key Concepts Learned

- **`docker network ls`** shows all Docker networks
- **`docker network create <name>`** creates a custom bridge network
- **`docker network connect <network> <container>`** adds a container to a network without stopping it
- **`docker network disconnect <network> <container>`** removes a container from a network
- **`docker inspect <container>`** shows detailed info including network membership and IP addresses
- Containers must be on the **same custom bridge network** to resolve each other's names
- The **default bridge network** does NOT support DNS resolution — only custom networks do
- A container can be on **multiple networks** simultaneously
- Docker's built-in DNS resolves **container names** (not image names) on shared custom networks

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
- **Confusing the lab container with the target containers:** The lab container is your workstation. The frontend-web and backend-api are the containers you're fixing. Docker commands you run in the lab container manage those other containers via the mounted socket.
