# Lab 044 — Solution Walkthrough — Blue-Green Deployment

## TLDR (Plain English)

**The problem:** Every time the team deploys a new version of the app, the site goes down for 10–30 seconds while the old version stops and the new one starts. Customers see errors during this gap. They want zero-downtime deployments.

**The setup we've inherited:** Two copies of the app are already running side by side — one called "blue" (the live version, v1) and one called "green" (the new version, v2). An nginx router sits in front of both and decides which one users actually reach. Right now, nginx is hardcoded to send everyone to blue. There's a script called `switch.sh` that's supposed to flip traffic between the two, but it's empty — just a placeholder.

**What we need to do:** Write `switch.sh` so it can flip nginx between pointing at blue and pointing at green, and do it without dropping any user requests in the process. The trick is making the switch *safe* — we need to check the new version is actually working before we send real users to it, and we need nginx to swap over gracefully rather than slamming the door on anyone mid-request.

**The five things the script needs to do:**
1. Work out which environment is currently live (read the nginx config to see)
2. Health-check the *other* environment to make sure it's actually responding
3. If healthy, rewrite nginx's config to point at the other environment
4. Tell nginx to reload its config — this is the actual moment of switchover, and nginx does it gracefully (existing requests finish on the old backend, new requests go to the new one)
5. Leave the old environment running, so if the new version turns out to be broken under real traffic we can flip back instantly

---

## You've Just Been Handed This Ticket

You've picked up a ticket that reads:

> *"Deployments cause 10–30 seconds of downtime. We've set up blue/green infrastructure but the switching script is a stub. Implement zero-downtime switching."*

You've never seen this codebase before. Let's work through what an engineer actually does on arrival — not "here's the answer", but the reasoning chain from a cold start.

---

## Step 0 — Get the lay of the land

First instinct on any cold ticket: **see what's actually in the working directory.** Don't read code yet, just see what files exist.

```bash
ls -la
```

You should see at least these files: `docker-compose.yml`, `nginx.conf`, `switch.sh`, `validate.sh`. Three of them are configuration / source, one's a validator.

The next move is to read each file in turn. Order matters — start with the thing that orchestrates everything, which is the compose file.

```bash
cat docker-compose.yml
```

### What `docker-compose.yml` tells us

You'll see three services defined: `app-blue`, `app-green`, and `router`.

- `app-blue` runs `myapp:v1` and exposes port **8001** on the host (mapped to **8080** inside the container)
- `app-green` runs `myapp:v2` and exposes port **8002** on the host (mapped to **8080** inside the container)
- `router` runs `nginx:alpine`, owns port **80**, and mounts `./nginx.conf` from the host into the container at `/etc/nginx/conf.d/default.conf`

**What can we infer just from this?**

- There are **two copies of the same app running at the same time** (different image versions). That's unusual unless someone is doing blue/green or canary deployments.
- The `router` service depending on both apps and owning port 80 strongly suggests it's the user-facing entry point.
- The volume mount on the router is significant — it means the nginx config lives on the host filesystem, not baked into the container image. That's important later because it determines where edits need to happen.

**Key question to file away:** *"If I edit `./nginx.conf` on the host, does the running router container see the change?"* Yes — because it's a bind mount, the container reads the same file the host writes to. But **the running nginx process won't reload automatically** — we'll come back to that.

### What `nginx.conf` tells us

```bash
cat nginx.conf
```

```nginx
upstream app {
    server app-blue:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://app;
    }
}
```

Reading this carefully:
- `upstream app { ... }` defines a backend pool called "app". Right now that pool contains one server: `app-blue` on port 8080.
- The `server` block listens on port 80 (matching the port mapping in the compose file) and forwards every request to the upstream pool.
- **There's no mention of `app-green` anywhere.** Nginx has no idea green exists.

**So this is the source of the problem the ticket described.** The infrastructure is "blue/green" in name only — both environments exist, but nginx is hardcoded to one of them. To switch, we need to change `app-blue:8080` to `app-green:8080` (or vice versa) and get nginx to pick up the change.

### What `switch.sh` tells us

```bash
cat switch.sh
```

```bash
#!/bin/bash
# Implement blue/green deployment switching for zero-downtime releases.
# Should toggle traffic between blue and green environments safely.

CURRENT_ENV=${1:-blue}

echo "TODO: Implement blue/green switching"
```

It's an empty stub. The comments give us the requirement, the variable `CURRENT_ENV` looks like a placeholder for "which environment to switch to", and the body just echoes a TODO. **This is the file we need to write.**

---

## Step 1 — Get the environment running so we have something to test against

Before writing any script, we need both environments actually running. You can't health-check or test a switch script against containers that aren't there.

```bash
docker compose up -d
```

**Command breakdown:**

| Component | Meaning |
|---|---|
| `docker compose` | Tool for managing multi-container apps defined in `docker-compose.yml` |
| `up` | Create and start the services |
| `-d` | Detached mode — run in background, give us our shell back |

Verify they're all running:

```bash
docker compose ps
```

You should see `app-blue`, `app-green`, and `router` all in `Up` state. If any are missing or restarting, fix that before going any further — the rest of the lab assumes all three are healthy.

### Sanity check the routing as it stands

Before we change anything, prove the current state matches our reading of the config:

```bash
curl http://localhost/
curl http://localhost:8001/
curl http://localhost:8002/
```

The first should hit the router (port 80) and reach blue. The second hits blue directly. The third hits green directly. All three should respond with something — even if it's just an nginx default page or an app error, the point is to confirm all three endpoints are alive.

**If `curl http://localhost/` gives the same response as `curl http://localhost:8001/`, that confirms the router is forwarding to blue.** If it gives the same response as `:8002`, the lab's been set up wrong and we should investigate before continuing.

---

## Step 2 — Plan the script before writing it

Now we know what we're working with, let's plan. The ticket says "implement zero-downtime switching." Walk through what the script logically has to do — and crucially, *why* each step exists.

### Step-by-step reasoning

**1. Should the script know in advance which way to switch, or work it out?**

Two options: (a) the user passes in `blue` or `green` as an argument, or (b) the script reads the current config and toggles to the opposite. Option (b) is more idempotent — running the script always means "switch to the other one", and you can't accidentally switch *to* the environment you're already on. Less foot-gun. Let's go with (b).

> **How would I know this?** Real-world experience or talking to someone who's run blue/green before. The decision principle is: scripts that infer state from the system are safer than scripts that trust user input, because users mistype things at 2am during incidents.

**2. How do we determine which environment is currently active?**

Read `nginx.conf` and `grep` for `app-blue`. If it's there, blue is active and we need to switch to green. If not, green is active and we switch to blue.

> **Where do we look?** The `upstream app` block in `nginx.conf` is the source of truth — whatever server is listed there is the one receiving traffic.

**3. Before switching, do we just trust that the target environment works?**

No. This is the critical safety gate. If we deploy a broken green version and switch traffic to it, we've just caused the outage we're trying to prevent. We need to **health-check the target before sending any users there.**

> **How do we health-check?** A simple `curl` to the target's port. If it responds with a 2xx HTTP status, it's alive. We should retry a few times because the new container might still be starting up.

**4. How do we actually switch?**

Edit `nginx.conf` to point the upstream at the other environment, then tell nginx to reload its config.

> **Wait — why doesn't nginx pick up the file change automatically?** Nginx reads the config once, at startup, and keeps it in memory. Changing the file on disk does nothing until you tell nginx to re-read it. There are two ways to do this: restart nginx (drops connections — bad), or `nginx -s reload` (graceful — completes existing requests on the old config before workers using the new config take over).

**5. How do we edit the nginx.conf file from inside the script?**

We need to change `app-blue` to `app-green` (or vice versa). `sed` with in-place editing is the standard tool for this — one line, no temporary files.

**6. How do we run `nginx -s reload`?**

This is where the bind-mount detail from Step 0 matters. The nginx process is running *inside the router container*, not on the host. Running `nginx -s reload` from the host would try to reload an nginx that doesn't exist there. We need `docker compose exec router nginx -s reload` to run the command **inside the router container** where nginx actually lives.

> **How would I know this?** Mental model: containers are isolated processes. If a process runs in a container, you have to enter the container (or use `exec`) to talk to it. `docker compose exec <service> <command>` is the standard way.

**7. What about rollback?**

The script should be its own rollback. Because Step 1 reads the current state and toggles to the opposite, running `./switch.sh` once switches blue→green, running it again switches green→blue. No separate rollback script needed.

---

## Step 3 — Write the script

Now we write `switch.sh` based on the plan above.

```bash
#!/bin/bash
set -e

# --- 1. Determine which environment is currently active ---
if grep -q "app-blue" nginx.conf; then
    CURRENT="blue"
    TARGET="green"
    TARGET_PORT=8002
else
    CURRENT="green"
    TARGET="blue"
    TARGET_PORT=8001
fi

echo "Current: $CURRENT  →  Switching to: $TARGET"

# --- 2. Health-check the target before switching ---
echo "Health-checking $TARGET on port $TARGET_PORT..."
HEALTHY=false
for i in $(seq 1 10); do
    if curl -sf "http://localhost:$TARGET_PORT/" > /dev/null; then
        HEALTHY=true
        echo "  $TARGET responded on attempt $i"
        break
    fi
    echo "  attempt $i/10 — waiting..."
    sleep 2
done

if [ "$HEALTHY" != "true" ]; then
    echo "ERROR: $TARGET is not responding. Aborting switch."
    exit 1
fi

# --- 3. Update nginx config to point at the target ---
sed -i "s/app-$CURRENT/app-$TARGET/g" nginx.conf

# --- 4. Reload nginx inside the router container ---
docker compose exec router nginx -s reload

echo "Done. Traffic is now on $TARGET. $CURRENT is still running for rollback."
```

### Command breakdowns

**`set -e`**

| Component | Meaning |
|---|---|
| `set` | Bash builtin for changing shell options |
| `-e` | Exit immediately if any command returns a non-zero status |

This means if any step fails (health check, sed, reload), the script stops rather than ploughing on and leaving things in a broken state.

**`grep -q "app-blue" nginx.conf`**

| Component | Meaning |
|---|---|
| `grep` | Search for a pattern in a file |
| `-q` | Quiet — don't print matches, just set the exit code (0 = found, 1 = not found) |
| `"app-blue"` | The pattern to look for |
| `nginx.conf` | The file to search in |

We use `-q` because we only care *whether* the pattern exists, not what the matching line says.

**`curl -sf "http://localhost:$TARGET_PORT/"`**

| Component | Meaning |
|---|---|
| `curl` | HTTP client |
| `-s` | Silent — don't show progress bar or error messages |
| `-f` | Fail (return non-zero exit code) on HTTP errors like 4xx/5xx |
| `"http://localhost:$TARGET_PORT/"` | The URL to request |

`-f` is what makes this a real health check. Without it, `curl` returns 0 (success) even if the server returns a 500 error, because curl considers "I successfully delivered the response" as success regardless of what the response said.

**`sed -i "s/app-$CURRENT/app-$TARGET/g" nginx.conf`**

| Component | Meaning |
|---|---|
| `sed` | Stream editor — text transformation tool |
| `-i` | In-place — edit the file directly rather than printing to stdout |
| `"s/.../.../g"` | Substitution: `s/old/new/g` replaces `old` with `new` globally on every matching line |
| `app-$CURRENT` | The string to search for, with the variable substituted (e.g. `app-blue`) |
| `app-$TARGET` | The replacement, with the variable substituted (e.g. `app-green`) |
| `nginx.conf` | The file to edit |

Note we use double quotes (`"..."`) not single quotes, because we need bash to expand `$CURRENT` and `$TARGET` before sed sees them.

**`docker compose exec router nginx -s reload`**

| Component | Meaning |
|---|---|
| `docker compose exec` | Run a command inside a running compose service container |
| `router` | The service name (from docker-compose.yml) |
| `nginx -s reload` | The command to run inside that container — sends the reload signal to the nginx master process |

`nginx -s reload` is graceful: nginx starts new worker processes with the new config, the old workers finish their in-flight requests, and then exit. No connections are dropped.

---

## Step 4 — Make it executable and test it

```bash
chmod +x switch.sh
```

**`chmod +x`** adds the execute permission so we can run the script as `./switch.sh` rather than having to type `bash switch.sh` every time.

Run it:

```bash
./switch.sh
```

Expected output (roughly):

```
Current: blue  →  Switching to: green
Health-checking green on port 8002...
  green responded on attempt 1
Done. Traffic is now on green. blue is still running for rollback.
```

Now verify the switch actually happened:

```bash
curl http://localhost/
curl http://localhost:8001/
curl http://localhost:8002/
```

`curl http://localhost/` should now return the same content as `curl http://localhost:8002/` (green), not `:8001/` (blue).

Confirm by reading the nginx config:

```bash
cat nginx.conf
```

It should now say `server app-green:8080;` where it used to say `app-blue`.

### Test the rollback

Run the script again:

```bash
./switch.sh
```

This should switch back to blue. Verify:

```bash
curl http://localhost/
cat nginx.conf
```

If both flips work cleanly, the script is doing its job.

---

## Step 5 — Run the validator

```bash
bash validate.sh
```

Or if `lab validate` is set up:

```bash
lab validate fundamentals/lab-044-blue-green-deployment
```

(adjust path to match the actual lab directory).

---

## A subtlety worth understanding: why `nginx -s reload` is "zero-downtime"

When you run `nginx -s reload`:

1. The nginx **master** process re-reads the config file
2. It starts new **worker** processes with the new config
3. The new workers immediately start accepting *new* incoming connections
4. The old workers stop accepting new connections, but **continue serving requests already in flight**
5. Once the old workers finish their in-flight requests, they exit

The net effect: every request gets a complete, valid response. No connection is dropped mid-stream. From a user's perspective, the switch is invisible.

Compare this with `docker compose restart router`, which kills the nginx process and starts a new one — any request mid-flight at that moment would get a connection reset. That's the opposite of zero-downtime.

---

## Docker Lab vs Real Life

In production environments, the switching mechanism usually lives somewhere more sophisticated than nginx:

- **AWS ALB target groups** — register/deregister instances from target groups, the load balancer drains connections gracefully
- **Route 53 weighted DNS** — shift percentages of traffic over time (canary), or flip 100% (blue-green)
- **Service mesh (Istio, Linkerd)** — virtual service rules can shift traffic between subsets at the request level
- **Kubernetes services with selector changes** — change the label selector on a service to point at a different deployment

The pattern is the same everywhere though: **two environments, a router in front, a way to flip the router, and a health gate before flipping.**

A few things this lab doesn't capture that bite in production:

- **Database migrations** — if the new version requires a schema change that the old version can't read, you can't roll back. The mitigation is to make all migrations backward-compatible (additive only) for at least one release cycle.
- **Stateful sessions** — if user sessions live in memory on the app server, switching loses them. Use Redis or similar so sessions survive the switch.
- **Warm-up** — new containers are cold (caches empty, JIT not warmed up). Some teams send a small percentage of traffic to green for a few minutes before flipping fully, to warm caches.
- **Cost** — running two full environments doubles infrastructure cost. Some teams only spin up green during deploys and tear it down afterwards.

---

## Key Concepts Learned

- **Blue-green deployment** is two identical environments with a router in front. Deploy to the inactive one, health-check, then flip the router. The downtime gap disappears because there's no "stop old, start new" — both are already running.
- **`nginx -s reload`** is graceful: existing requests finish on the old config, new requests hit the new config. Zero dropped connections.
- **Health-check before switching** — the cheapest way to cause an outage during a blue-green deploy is to switch traffic to a broken environment without checking it first.
- **Idempotent toggle scripts** — making the script "switch to whichever I'm not on" rather than "switch to X" eliminates an entire class of operator error.
- **Bind mounts vs container internals** — when nginx config is bind-mounted from the host, the host can edit the file but only the container can tell its nginx process to reload.

## Common Mistakes

- **Forgetting that nginx caches config in memory.** Editing `nginx.conf` on disk does nothing until you reload. The reload is what actually flips traffic.
- **Running `nginx -s reload` on the host instead of inside the container.** The host probably doesn't have nginx installed at all, or has a different one — the relevant nginx is inside the router container, so the reload command must run there too.
- **Stopping the old environment immediately after switching.** If the new version turns out to have problems under real traffic, you want the old one still warm and ready to take traffic back. Leave it running for at least 30 minutes after a switch.
- **Skipping the health check because "it worked locally".** The point of the health gate isn't that it usually catches problems — it's that the *one time* it does, it saves you an outage.
- **Schema changes that break the old version.** If green requires a database column that blue's queries fail on, rolling back to blue won't work. Migrations should always be backward-compatible.

---

## Cleanup

When you're done with the lab, leave the working directory in the original broken state for repeatability:

```bash
docker compose down
git checkout -- switch.sh nginx.conf
```

**`docker compose down`** stops and removes the containers (the images are kept).
**`git checkout -- <file>`** restores the file to whatever's committed in the repo, undoing any edits you made to `switch.sh` and `nginx.conf` so the lab is fresh for the next run.
