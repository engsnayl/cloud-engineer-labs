# Solution Walkthrough — Docker Networking Broken

## The Problem

Two containers — `frontend-web` and `backend-api` — need to communicate with each other, but they can't. The reason is that they are on **separate Docker networks**:

- `backend-api` is on `backend-net`
- `frontend-web` is on `frontend-net`

Docker containers can only communicate directly with other containers on the **same network**. Containers on different networks are completely isolated from each other — they can't resolve each other's hostnames and they can't reach each other's IP addresses. This is by design: network isolation is a core Docker security feature.

The fix is to connect both containers to a shared network so they can talk to each other.

## Thought Process

When two containers can't communicate, an experienced engineer checks:

1. **Are both containers running?** `docker ps` to verify both are up.
2. **What networks are they on?** `docker inspect <container> --format '{{json .NetworkSettings.Networks}}'` shows the network(s) each container is attached to.
3. **Are they on the same network?** If not, that's your answer. Containers on different networks can't talk to each other.
4. **Connect them to a shared network** — either connect one container to the other's network, or create a new shared network and connect both.

Docker's built-in DNS only works within a single network. When containers share a custom bridge network, they can reach each other by container name (e.g., `curl http://backend-api:3000`). This name-based discovery doesn't work across different networks.

## Step-by-Step Solution

### Step 1: Run the setup script to create the broken environment

```bash
/opt/setup-broken-network.sh
```

**What this does:** Creates the two Docker networks (`frontend-net` and `backend-net`) and starts the two containers on separate networks. After this, the containers are running but can't communicate.

### Step 2: Verify both containers are running

```bash
docker ps --filter "name=backend-api" --filter "name=frontend-web"
```

**What this does:** Lists both containers and their status. Both should show "Up."

### Step 3: Check which networks each container is on

```bash
docker inspect backend-api --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker inspect frontend-web --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

**What this does:** Shows the network name(s) for each container using Go template formatting. You'll see `backend-api` is on `backend-net` and `frontend-web` is on `frontend-net`. They share no common network, which is why they can't communicate.

### Step 4: Try to reach the backend from the frontend (to confirm the problem)

```bash
docker exec frontend-web bash -c "curl -s --connect-timeout 2 http://backend-api:3000" 2>&1
```

**What this does:** Tries to reach `backend-api` from inside the `frontend-web` container. It will fail — either with a DNS resolution error (the hostname `backend-api` doesn't resolve) or a connection timeout. This confirms the network isolation.

### Step 5: Create a shared network (or use an existing one)

```bash
docker network create app-net
```

**What this does:** Creates a new Docker bridge network called `app-net`. This will be the shared network that both containers connect to. Docker's custom bridge networks provide automatic DNS resolution — containers on the same custom bridge can reach each other by name.

### Step 6: Connect both containers to the shared network

```bash
docker network connect app-net backend-api
docker network connect app-net frontend-web
```

**What this does:** Attaches each container to the `app-net` network **without stopping them**. This is a live operation — the containers get an additional network interface and can now communicate through `app-net`. They remain connected to their original networks too (a container can be on multiple networks).

### Step 7: Test connectivity from frontend to backend

```bash
docker exec frontend-web bash -c "curl -s http://backend-api:3000"
```

**What this does:** Tries again to reach `backend-api` from `frontend-web`. This time it should succeed — you'll see `{"status": "healthy", "service": "backend-api"}`. The containers can now resolve each other's names and communicate over the shared `app-net` network.

### Step 8: Verify the network configuration

```bash
docker network inspect app-net --format '{{range .Containers}}{{.Name}} {{end}}'
```

**What this does:** Lists all containers connected to `app-net`. You should see both `backend-api` and `frontend-web`, confirming they share this network.

## Docker Lab vs Real Life

- **Docker Compose networking:** In production, you'd typically use Docker Compose, which automatically creates a shared network for all services in the `docker-compose.yml` file. You rarely need to create networks manually. Services defined in the same Compose file can communicate by service name automatically.
- **Kubernetes networking:** In Kubernetes, all pods can communicate with each other by default (unless Network Policies restrict it). Service names are resolved through Kubernetes DNS. The networking model is fundamentally different from Docker's isolated networks.
- **Network security:** Docker's network isolation is a feature, not a bug. In production, you'd deliberately put different tiers on different networks — for example, the frontend on a public-facing network and the database on an internal-only network. You'd then selectively connect containers to the networks they need.
- **Network aliases:** In production, you might use `--network-alias` to give containers additional DNS names on a network. This is useful when migrating between container names or when multiple containers should respond to the same name.
- **Overlay networks:** In Docker Swarm or multi-host setups, you'd use overlay networks (instead of bridge networks) to span containers across multiple physical hosts.

## Key Concepts Learned

- **Docker containers on different networks can't communicate** — network isolation is a core Docker feature. Containers must share a network to talk to each other.
- **Custom bridge networks provide DNS resolution** — containers on the same custom bridge network can reach each other by container name. The default `bridge` network does NOT provide this — only custom networks do.
- **`docker network connect` adds a network without stopping the container** — this is a non-disruptive operation. The container gets an additional network interface.
- **Containers can be on multiple networks simultaneously** — this is useful for containers that need to bridge between tiers (e.g., an API server that talks to both the frontend network and the database network).
- **`docker network inspect` shows which containers are on a network** — essential for debugging connectivity issues

## Common Mistakes

- **Using the default `bridge` network** — the default Docker bridge network doesn't provide DNS resolution between containers. You can only reach other containers by IP address, which is fragile. Always create and use custom bridge networks.
- **Stopping and recreating containers instead of connecting them** — `docker network connect` adds a network to a running container. There's no need to stop, remove, and recreate the container with a different `--network` flag.
- **Forgetting that DNS only works within a network** — if container A is on `net-1` and container B is on `net-2`, A can't resolve B's name even if A knows B exists. They must share at least one network.
- **Not verifying with `docker network inspect`** — after connecting containers, always verify the network configuration. A typo in the container name or network name would silently fail.
- **Exposing ports unnecessarily** — when containers are on the same network, they can reach each other directly on any port. You don't need `-p` port mapping for container-to-container communication. Port mapping (`-p 8080:3000`) is only needed to expose a container port to the Docker host.
