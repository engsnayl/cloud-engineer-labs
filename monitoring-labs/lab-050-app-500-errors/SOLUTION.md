# Lab 050 — Solution Walkthrough: Application Throwing 500 Errors

---

## TLDR (Plain English Summary)

A web application is returning HTTP 500 errors — but only on one endpoint (`/api/payments`), and only sometimes. The other endpoints work fine. The app hasn't crashed.

The reason: every time someone hits `/api/payments`, the code increments a database connection counter. The app only allows 5 connections at once. Connections are only released 30% of the time — so under any real traffic, the counter climbs past 5, new requests get rejected, and the user sees a 500 error.

**The fix isn't in the code itself — it's in the pool configuration and connection lifecycle management.**

Your job in this lab is to:
1. Investigate the logs to find the exact error
2. Confirm which endpoints are affected and which aren't
3. Understand *why* it only fails under load
4. Write a structured incident report documenting the findings and recommending fixes

---

## Step 0 — Start the Lab Environment

Before you can investigate anything, you need the application running. This lab uses Docker Compose to build and start the container.

```bash
cd ~/cloud-engineer-labs/monitoring-labs/lab-050-app-500-errors
docker compose up -d
```

**Command breakdown:**

| Part | What it does |
|------|--------------|
| `docker compose` | The Compose tool — reads `docker-compose.yml` in the current directory |
| `up` | Build the image (if needed) and start the container |
| `-d` | Detached mode — runs in the background so your terminal stays free |

**What happens when you run it:**

1. Compose reads `docker-compose.yml`
2. It sees `build: .` — so it builds a Docker image from the `Dockerfile` in the current directory
3. Once the image is built, it starts a container from it named `lab050-app-500-errors`
4. The `-d` flag means it runs in the background

**Expected output:**
```
[+] Building 12.3s (8/8) FINISHED
[+] Running 1/1
 ✔ Container lab050-app-500-errors  Started
```

> **Why Compose and not `docker run`?**
> Previous labs used `docker run` with pre-built images. This lab has its own application code and a `Dockerfile` that needs building first. Compose handles the build-then-run sequence in a single command. Without Compose you'd need to run `docker build` manually first, then `docker run` separately. As labs get more complex — especially when multiple containers need to work together — Compose becomes the standard way to manage them.

Now exec into the container — the incident report must be written from inside:

```bash
docker exec -it lab050-app-500-errors bash
```

**Command breakdown:**

| Part | What it does |
|------|--------------|
| `docker exec` | Run a command inside a running container |
| `-it` | `-i` keeps stdin open, `-t` allocates a terminal — together they give you an interactive shell |
| `lab050-app-500-errors` | The name of the container to exec into |
| `bash` | The command to run — opens a bash shell inside the container |

**Why do we exec in for this lab?**

The `validate.sh` script checks for the incident report using `docker exec "$CONTAINER" test -f /tmp/incident-report.txt` — meaning it's looking for the file **inside the container's filesystem**, not on your Pi. If you wrote the report to your Pi's `/tmp/`, validation would fail every time even though the file exists.

> **How to tell where you are:** Your prompt changes when you exec in. On the Pi it shows `engsnayl@pi:~$`. Inside the container it shows `root@<container-id>:/#`. When you see that, you're inside. This matters — running commands in the wrong place is one of the most common sources of confusion in this lab.

**The overall flow for this lab:**

```
Pi terminal      →  docker compose up -d
Pi terminal      →  docker exec -it lab050-app-500-errors bash
Inside container →  curl endpoints to check health and blast radius
Inside container →  exit  (docker logs only works from outside)
Pi terminal      →  docker logs ... | grep "ERROR"
Pi terminal      →  docker exec -it lab050-app-500-errors bash  (back in to write report)
Inside container →  cat > /tmp/incident-report.txt
Inside container →  exit
Pi terminal      →  lab validate monitoring-labs/lab-050-app-500-errors
```

---

## Learning Pathway — How to Think Through This

This is the kind of problem where you'd be handed a ticket saying "payments endpoint is broken, please investigate." There's no one telling you it's a connection pool issue. Here's how a real engineer works through it.

### Phase 1 — What are we actually dealing with?

> ⚠️ **Check your prompt before running anything.** You should see `root@<container-id>:/#` — not `engsnayl@pi`. If you're still on the Pi, run `docker exec -it lab050-app-500-errors bash` first. Running curl from the Pi won't work — the app is listening on port 8080 inside the container, and that port isn't exposed to the host. You'll get no output at all, which can be misleading.

**Start with the broadest question first: is the application even running?**

Before investigating *why* something's failing, confirm the process is alive. A 500 error from a running app is a completely different problem to a crashed app returning nothing.

```bash
curl -s http://localhost:8080/api/health
```

> If this returns `OK`, the app is running. The problem is in specific code paths, not the process itself. This narrows your investigation significantly — you're not dealing with an OOM kill, a crash loop, or a failed deployment.

**Then ask: which endpoints are failing?**

500 errors are a symptom, not a root cause. "The app is broken" is too broad. You need to establish the blast radius — is everything down, or just specific paths?

```bash
curl -s http://localhost:8080/api/users
curl -s http://localhost:8080/api/payments
```

**Expected output:**
```
{"users": []}
{"error": "Internal Server Error"}
```

> `/api/users` returning data but `/api/payments` returning an error tells you the issue is in the payments code path specifically — not infrastructure, not networking, not the web server. The blast radius is one endpoint.

---

### Phase 2 — What does the error actually say?

**Now go to the logs — but there's a catch in this lab.**

`docker logs` is a **host-side command**. It talks to the Docker daemon via the Docker socket — and from inside a container, you don't have access to that socket. Running `docker logs` from inside the container will return nothing at all, with no error message to tell you why.

You need to **exit the container first**, then run the log commands from your Pi terminal:

```bash
# Inside the container — exit back to Pi
exit

# Now on your Pi terminal
docker logs lab050-app-500-errors 2>&1 | grep "500"
docker logs lab050-app-500-errors 2>&1 | grep "ERROR"
```

**Command breakdown:**

| Part | What it does |
|------|--------------|
| `docker logs lab050-app-500-errors` | Fetches all logs (stdout + stderr) from the named container |
| `2>&1` | Redirects stderr (file descriptor 2) to stdout (file descriptor 1) — so both streams are captured together. Without this, error-level log lines written to stderr would be invisible to `grep` |
| `\| grep "500"` | Pipes the combined output to `grep`, filtering to only lines containing "500" |
| `\| grep "ERROR"` | Same pattern, filtering for lines with "ERROR" severity |

> **Why does `docker logs` only work from outside?** Docker CLI routes commands through the Docker socket (`/var/run/docker.sock`) to the host daemon. Inside a container, that socket isn't available — the container is isolated from the host's Docker daemon. This is the same reason you can't run `docker` commands from inside a container by default.

**What you expect to find:**

```
ERROR 500 GET /api/payments - DatabaseError: connection pool exhausted (used: 6, max: 5)
```

Break this down mentally when you see it:

- `ERROR 500` → severity and HTTP status code
- `GET /api/payments` → the specific endpoint — not all endpoints, just this one
- `DatabaseError` → the error class — a database problem, not application logic
- `connection pool exhausted` → the specific condition — the pool is full
- `(used: 6, max: 5)` → the evidence — 6 connections attempted, pool only allows 5

**Why does it say "used: 6" if the max is 5?**
The app tried to open a 6th connection, was denied, and logged the attempt. The number shown is what was requested, not what was granted.

---

### Phase 2b — What if the logs don't show anything useful?

If `docker logs` returns nothing or the output isn't clear enough, there's another technique: **find the running process and read the application code directly.**

Exec back into the container and run:

```bash
docker exec -it lab050-app-500-errors bash
ps aux
```

**Expected output:**
```
root   1   /bin/bash -c /opt/inject-faults.sh && tail -f /dev/null
root   7   /bin/bash /opt/inject-faults.sh
root   9   python3 /opt/app.py
```

**Command breakdown (`ps aux`):**

| Part | What it does |
|------|--------------|
| `ps` | Process status — lists running processes |
| `a` | Show processes from all users, not just the current one |
| `u` | Show in user-oriented format (includes user, CPU, memory) |
| `x` | Include processes not attached to a terminal (background processes) |

This tells you the app is a Python script at `/opt/app.py` and there's a fault injection script also running. Now read the application code directly:

```bash
cat /opt/app.py
```

Reading the source code tells you everything — exactly how the connection pool is implemented, why it exhausts, and what the log messages will say. In a real incident you won't always have access to source code, but when you do it's the most definitive way to confirm your hypothesis.

**What the code reveals:**

```python
DB_POOL = {"max": 5, "used": 0}
```
The pool is simulated as a simple counter with a max of 5.

```python
DB_POOL["used"] += 1
if DB_POOL["used"] > DB_POOL["max"]:
    # returns 500 error
```
Every request to `/api/payments` increments the counter. Once it exceeds 5, every subsequent request fails.

```python
if random.random() > 0.7:
    DB_POOL["used"] = max(0, DB_POOL["used"] - 1)
```
Connections are only released 30% of the time — so the counter climbs steadily until the pool is permanently exhausted.

---

### Phase 3 — Why does this only fail sometimes?

This is the critical insight. If you tested this endpoint with a single early request, it probably worked. So why does it fail now?

The pool counter starts at 0 and only climbs. The first 5 requests to `/api/payments` succeed. From the 6th request onwards, every request fails — because connections are only released 30% of the time, the counter never comes back down below 5 under normal usage.

**The broader pattern to remember:**

Intermittent failures that get progressively worse and eventually become permanent point to a **resource leak** — something being consumed but not reliably released. Connection pools, memory, file descriptors, and thread pools all fail this way. The symptom looks random at first but the underlying counter only ever moves in one direction.

This is different from a purely concurrent exhaustion scenario where the pool fills under load but recovers when traffic drops. Here the pool never recovers — which is why once the errors start, they don't stop.

---

### Phase 4 — Write the incident report

An incident report is not just a note to yourself. It's the artefact that gets handed to the team, shared in a post-mortem, or attached to a Jira ticket. It needs to stand alone.

> ⚠️ **Exec back into the container before writing the report.** The file must live at `/tmp/incident-report.txt` inside the container — not on your Pi. Writing it to your Pi's `/tmp/` is a common mistake that causes all validation checks to fail even though the file exists.

```bash
docker exec -it lab050-app-500-errors bash
```

Then write the report:

```bash
cat > /tmp/incident-report.txt << 'EOF'
# Incident Report: HTTP 500 Errors on Payment API

## Summary
Intermittent HTTP 500 errors on the /api/payments endpoint caused by database
connection pool exhaustion. Error rate reached approximately 15%.

## Affected Endpoint
/api/payments — the only endpoint experiencing failures.
/api/users and /api/health are unaffected.

## Root Cause
The database connection pool has a maximum of 5 connections. The /api/payments
endpoint increments the connection counter on every request but only releases
connections 30% of the time. The counter climbs past the maximum of 5 and
every subsequent request receives a connection pool exhausted error and returns
HTTP 500 to clients.

## Evidence
Application logs show:
  ERROR 500 GET /api/payments - DatabaseError: connection pool exhausted (used: 6, max: 5)

## Impact
- Payment processing is intermittently failing
- Approximately 15% of payment requests receive HTTP 500 errors
- Other endpoints (/api/users, /api/health) are not affected

## Recommended Fix
1. Increase the database connection pool size (e.g., max: 20)
2. Fix connection release logic — connections must be returned on every request, not 30%
3. Add connection timeouts so idle connections are returned to the pool automatically
4. Add monitoring and alerting on pool utilisation before it hits 100%
5. Add circuit breaker pattern to prevent cascading failures
EOF
```

**Command breakdown:**

| Part | What it does |
|------|--------------|
| `cat > /tmp/incident-report.txt` | Redirects output into a new file — overwrites if it already exists |
| `<< 'EOF'` | Heredoc — everything until the closing `EOF` is treated as literal input. Single quotes prevent variable expansion inside the block |
| `EOF` on its own line | Signals the end of the heredoc |

> Heredocs are the standard way to write multi-line content to a file in a single shell command. You'll see this constantly in DevOps scripts, CI/CD pipelines, and Terraform provisioners.

---

### Phase 5 — Validate your work

Exit the container, then run validation from your Pi terminal:

```bash
# Inside the container
exit

# Back on your Pi terminal
lab validate monitoring-labs/lab-050-app-500-errors
```

> **Why exit first?** The lab runner uses `docker exec` internally to reach into the container for each check — it's designed to be run from outside.

**What the validator is checking under the hood:**

| Check | What it looks for |
|-------|-------------------|
| Incident report exists | `test -f /tmp/incident-report.txt` inside the container |
| Root cause documented | Report contains "pool", "connection", or "database" |
| Affected endpoint documented | Report contains "payment" |
| Application still running | `curl http://localhost:8080/api/health` returns "OK" |

**Expected output when all 4 pass:**
```
Running validation checks...

  ✅  Incident report exists at /tmp/incident-report.txt
  ✅  Report identifies database connection pool as root cause
  ✅  Report identifies /api/payments as affected endpoint
  ✅  Application is still running

Results: 4 passed, 0 failed
```

---

## Full Step-by-Step Command Reference

```bash
# ── FROM YOUR PI TERMINAL ──────────────────────────────────
cd ~/cloud-engineer-labs/monitoring-labs/lab-050-app-500-errors
docker compose up -d
docker exec -it lab050-app-500-errors bash

# ── NOW INSIDE THE CONTAINER ───────────────────────────────

# 1. Confirm the application is running
curl -s http://localhost:8080/api/health

# 2. Check which endpoints are affected
curl -s http://localhost:8080/api/users
curl -s http://localhost:8080/api/payments

# 3. Exit — docker logs only works from the Pi
exit

# ── BACK ON YOUR PI TERMINAL ───────────────────────────────

# 4. Filter logs for errors
docker logs lab050-app-500-errors 2>&1 | grep "500"
docker logs lab050-app-500-errors 2>&1 | grep "ERROR"

# Optional: if logs are unclear, read the source directly
docker exec -it lab050-app-500-errors bash
ps aux          # find the process and where it lives
cat /opt/app.py # read the code to confirm root cause
exit

# ── BACK ON YOUR PI TERMINAL ───────────────────────────────

# 5. Exec back in to write the incident report inside the container
docker exec -it lab050-app-500-errors bash

cat > /tmp/incident-report.txt << 'EOF'
[report content — see Phase 4 above]
EOF

# 6. Exit and validate
exit
lab validate monitoring-labs/lab-050-app-500-errors
```

---

## Docker Lab vs Real Life

- **`docker logs` is always host-side** — in production you'd use a log aggregator (Datadog, CloudWatch, ELK) that collects container logs automatically. You'd never need to exec in to read them.
- **APM tools:** Tools like Datadog APM, New Relic, or Jaeger trace each request through every service. You'd see the exact query that timed out and how long it held the connection.
- **Connection pool monitoring:** Production databases expose pool metrics (active, idle, waiting). A Grafana dashboard showing pool utilisation trending toward 100% lets you respond *before* failures start.
- **PgBouncer / ProxySQL:** Production systems often put a connection pooler between the application and database — it multiplexes hundreds of app connections onto a smaller number of database connections, making exhaustion much harder to trigger.
- **Alerting thresholds:** Set alerts at 70% pool utilisation (warning) and 90% (critical). This gives the team time to act before exhaustion causes 500s.

---

## Key Concepts

- **`docker logs` is host-side only** — it talks to the Docker daemon via the socket, which isn't accessible from inside a container. Always run it from your Pi terminal.
- **Check your prompt** — `engsnayl@pi` means you're on the Pi; `root@<id>:/#` means you're inside the container. Many errors in this lab come from running commands in the wrong place.
- **The incident report lives inside the container** — validate.sh checks `/tmp/` inside the container, not on the Pi. Writing it to the wrong `/tmp/` is a silent failure.
- **Filter logs immediately** — `grep "ERROR"` and `grep "500"` get you to the signal in seconds. Never scroll.
- **Read the message, not just the code** — `500` tells you something broke. `connection pool exhausted (used: 6, max: 5)` tells you exactly what and why.
- **Resource leaks look intermittent at first** — works for the first few requests, then fails permanently. The counter only goes up; recovery never happens.
- **`ps aux` + `cat` is a valid investigation technique** — when logs aren't accessible, find the process, find the code, read it directly.

---

## Common Mistakes

- **Running `docker logs` from inside the container** — returns nothing, no error. Exit first, then run it from the Pi.
- **Writing the incident report to the Pi's `/tmp/`** — the file exists but validation still fails because validate.sh looks inside the container. Always exec in before writing the report.
- **Running curl from the Pi** — port 8080 isn't exposed to the host. Curl only works from inside the container where localhost means the container's own network. From the Pi you get no output and no error — just silence.
- **Looking at status codes only** — `500` tells you nothing actionable. The log message tells you everything.
- **Testing with a single early request** — the first 5 requests to `/api/payments` succeed. The fault only becomes visible after the pool counter climbs past 5.
- **Incident reports without recommended actions** — finding the problem is half the job. The report must include what to do about it.

---

## Cleanup

From your Pi terminal, in the lab directory:

```bash
docker compose down
```

> This stops and removes the container. The incident report inside `/tmp/` disappears with it — containers don't persist filesystem changes after removal unless you've used a volume. `docker compose down` is the clean equivalent of `docker stop` + `docker rm` for Compose-managed containers.
