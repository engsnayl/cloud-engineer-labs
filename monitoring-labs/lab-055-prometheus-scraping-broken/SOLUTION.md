# Lab 055 — Prometheus Scraping Broken: Solution Walkthrough

---

## TLDR Summary

You've been handed an incident ticket: Grafana dashboards are empty, Prometheus shows 0 of 3 targets UP, and alerting is blind. Prometheus itself is running fine — the problem is entirely in `prometheus.yml`, the configuration file that tells Prometheus what to scrape, where to find it, and how often.

There are four bugs in the file:

1. **Scrape interval set to 600 seconds (10 minutes)** — Prometheus collects data so infrequently that dashboards are nearly empty and short-lived incidents are completely invisible. This bug is silent — it produces no error message.
2. **Wrong port for the app targets** — the config points at port `9090` (Prometheus's own port) instead of `8080` where the apps actually serve their metrics. Every connection is refused.
3. **Wrong metrics path** — the config asks for `/api/metrics` but the apps expose metrics at `/metrics`. Prometheus gets a 404 on every scrape attempt.
4. **Hostname typo for node exporter** — the config says `node_exporter` (underscore) but the Docker Compose service is named `node-exporter` (hyphen). Docker's DNS can't resolve it.

Fix all four in `prometheus.yml`, restart Prometheus, and all targets come up green.

---

## Background — What Is Prometheus?

Before diving into the fix, it helps to understand what Prometheus actually is and why it exists.

Imagine you have five servers, three applications, and a database all running at once. How do you know if any of them are struggling? You could SSH into each one and check manually — but that's not realistic at scale, and you'd miss anything that happened between checks.

**Prometheus is a central metrics collector.** It works on a pull model — every few seconds it reaches out to each of your services and asks "how are you doing?" Each service responds with a snapshot of numbers: requests handled, memory used, errors seen. Prometheus stores all of that over time so you can ask questions like "when did CPU spike?" or "how long has the error rate been elevated?"

**The three components in this lab:**

| Component | What it does |
|---|---|
| **Prometheus** | The core collector — scrapes metrics from targets and stores them |
| **Node Exporter** | A small agent that exposes the host machine's metrics (CPU, RAM, disk) in a format Prometheus can scrape |
| **Grafana** | The dashboard layer — reads from Prometheus and draws the graphs you actually look at |

**`prometheus.yml`** is the control file. It tells Prometheus what to scrape, where to find it (hostname + port), what URL path to request, and how often to collect. Get any of those wrong and Prometheus either can't reach the target or collects data too infrequently to be useful.

---

## Background — What Is Docker Compose?

Docker on its own runs a single container at a time. Docker Compose is for when you need multiple containers that work together.

In this lab you have five containers running simultaneously — Prometheus, Grafana, Node Exporter, app1, and app2. Each is a separate container, but they all need to talk to each other on the same network and start together. Managing that with raw Docker commands would be painful. Compose lets you describe the entire stack in one file — `docker-compose.yml` — and bring everything up or down with a single command.

**Important:** `docker compose` commands must be run from the directory that contains `docker-compose.yml`. Running them from anywhere else produces `no configuration file provided: not found`.

**Core Compose commands used in this lab:**

| Command | What it does |
|---|---|
| `docker compose ps` | Lists all containers in the stack and their current status |
| `docker compose restart prometheus` | Restarts the Prometheus container — required to pick up config changes |
| `docker compose down` | Stops and removes all containers |

---

## The Investigative Learning Pathway

This is how an experienced engineer approaches this incident — not "go fix the config" but a methodical process of finding out *what* is broken and *why* before touching anything.

---

### Step 0: Navigate to the lab directory

All `docker compose` commands must be run from the directory containing `docker-compose.yml`. Start by navigating there:

```bash
cd ~/cloud-engineer-labs/monitoring-labs/lab-055-prometheus-scraping-broken
```

Every command in this walkthrough is run from this directory.

---

### Step 1: Confirm the environment is actually running

Before anything else, establish what the system is doing. Don't assume the containers are up.

```bash
docker compose ps
```

**Example output:**
```
NAME                   IMAGE                        COMMAND              SERVICE         STATUS
lab055-app1            lab-055-...-app1             "python3 /app.py"    app1            Up 19 minutes   0.0.0.0:8081->8080/tcp
lab055-app2            lab-055-...-app2             "python3 /app.py"    app2            Up 19 minutes   0.0.0.0:8082->8080/tcp
lab055-node-exporter   prom/node-exporter:latest    "/bin/node_exporter" node-exporter   Up 19 minutes   0.0.0.0:9100->9100/tcp
lab055-prometheus      prom/prometheus:latest       "/bin/prometheus…"   prometheus      Up 19 minutes   0.0.0.0:9090->9090/tcp
```

**How to read the PORTS column:**

The `->` means: host port on the left, container port on the right. So `0.0.0.0:8081->8080/tcp` means the Pi exposes port 8081 externally, which maps to port 8080 inside the container. Prometheus talks to the containers on their *internal* ports — so the port you care about for the config is the number on the **right** side of the arrow.

**What this output already tells you before opening any config file:**

| Container | Internal port | Correct hostname |
|---|---|---|
| app1 | 8080 | app1 |
| app2 | 8080 | app2 |
| node-exporter | 9100 | node-exporter |
| prometheus | 9090 | prometheus |

If any container shows as `Exited` or `Restarting` here, you have a different problem — a container crash or bad YAML syntax — and that needs resolving before anything else.

**Then confirm Prometheus's web interface is responding:**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090
```

| Part | What it does |
|---|---|
| `curl` | Makes an HTTP request |
| `-s` | Silent mode — suppresses the progress bar |
| `-o /dev/null` | Throws away the response body — we only care about the status code |
| `-w "%{http_code}"` | Prints just the HTTP status code after the request completes |
| `http://localhost:9090` | Prometheus's web interface address |

**What the response means:**

| Response | Meaning |
|---|---|
| `200` | Prometheus UI is up and responding normally |
| `302` | Prometheus is redirecting you to `/graph` — this is normal, Prometheus is alive |
| `000` or `connection refused` | Prometheus is not responding — container may be crashed |

A `302` is completely normal here. Prometheus redirects the root path to its graph UI. This is not an error.

---

### Step 2: Check the targets page — your primary diagnostic tool

The single most useful thing in Prometheus for diagnosing scrape failures is the targets endpoint. It shows every configured target, its current state, and the exact error message for anything that's failing.

**In a non-headless environment** (where you have browser access) you'd simply open:
```
http://localhost:9090/targets
```

**In a headless environment** (SSH'd into a server with no browser, as in this lab) use the API directly:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E "health|lastError|job"
```

| Part | What it does |
|---|---|
| `curl -s` | Makes an HTTP request, `-s` suppresses the progress bar |
| `http://localhost:9090` | Address of your Prometheus instance |
| `/api/v1/targets` | The Prometheus API endpoint that returns all configured scrape targets and their health as JSON |
| `\|` | Pipes the output of curl into the next command |
| `python3 -m json.tool` | Python's built-in JSON formatter — makes raw compressed JSON human-readable with proper indentation |
| `\|` | Pipes the formatted JSON into the next command |
| `grep -E` | Searches through text line by line, `-E` enables extended regex to match multiple patterns at once |
| `"health\|lastError\|job"` | Prints any line containing `health`, `lastError`, or `job` — the three fields that tell you what's broken and where |

> **In practice:** Nobody types this command from memory. In a real environment it would live in a runbook, a cheat sheet, or a shell alias. The important thing is understanding *what you're querying and why* — not memorising the syntax.

**Example output:**
```
"job": "app"
"lastError": "Get \"http://app1:9090/api/metrics\": dial tcp 172.20.0.2:9090: connect: connection refused",
"health": "down",
"job": "app"
"lastError": "Get \"http://app2:9090/api/metrics\": dial tcp 172.20.0.3:9090: connect: connection refused",
"health": "down",
"job": "node"
"lastError": "Get \"http://node_exporter:9100/metrics\": dial tcp: lookup node_exporter on 127.0.0.11:53: no such host",
"health": "down",
"job": "prometheus"
"lastError": "",
"health": "up",
```

**Reading the error messages:**

| Error message | What it means | Which bug |
|---|---|---|
| `connection refused` on port `9090` | Nothing is listening on that port in the app containers — and the wrong path is visible in the URL too | Bugs 2 & 3 |
| `lookup node_exporter: no such host` | Docker DNS can't resolve this hostname — underscore vs hyphen mismatch | Bug 4 |
| `lastError: ""` and `health: up` | No error — this target is working fine | None |

**Important:** You will only see three error messages here, not four. Bug 1 (scrape interval) produces no error — Prometheus is scraping successfully, just far too infrequently. The only way to catch it is by inspecting the config directly or noticing that dashboards have almost no data points despite targets showing as UP. This makes it the sneakiest of the four bugs.

You now have a complete map of what's broken before opening a single config file.

---

### Step 3: Inspect the config file

Now open `prometheus.yml` to see the bugs directly:

```bash
cat prometheus.yml
```

**The broken config:**
```yaml
# Prometheus configuration — BROKEN
global:
  scrape_interval: 600s
  evaluation_interval: 600s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'app'
    static_configs:
      - targets: ['app1:9090', 'app2:9090']
    metrics_path: '/api/metrics'

  - job_name: 'node'
    static_configs:
      - targets: ['node_exporter:9100']
```

Every bug is visible here. Map each one against what the error messages already told you:

| Line in config | Bug | Evidence you already had |
|---|---|---|
| `scrape_interval: 600s` | 10 minutes — far too long | Validator flagged it; no error message produced |
| `targets: ['app1:9090', 'app2:9090']` | Wrong port | `docker compose ps` showed internal port is 8080 |
| `metrics_path: '/api/metrics'` | Wrong path | Error message showed this path in the failed URL |
| `targets: ['node_exporter:9100']` | Underscore in hostname | Error message said `lookup node_exporter: no such host` |

> **Note:** In a real incident the comment `# Prometheus configuration — BROKEN` wouldn't be there. The file would look like a normal config and you'd have to spot the bugs yourself — which is exactly what the investigative pathway trains you to do.

---

### Step 4: Understand each bug before fixing it

#### Bug 1 — Scrape interval too long

**Why does this matter?** Prometheus doesn't stream metrics — it polls. Every `scrape_interval` seconds it reaches out to each target and requests a fresh snapshot. At 600 seconds (10 minutes) you get one data point per target every 10 minutes. A Grafana dashboard covering the last 15 minutes has at most 1-2 data points — which often renders as nothing at all. Any incident that starts and resolves within 10 minutes is completely invisible.

**What should it be?** 15 seconds is the standard Prometheus default and a safe starting point. In practice:

| Interval | When it's appropriate |
|---|---|
| 15s | Development, labs, general purpose monitoring where you need good dashboard resolution |
| 30-60s | Production environments with many targets, where reducing load and storage matters |
| Under 15s | Rarely justified — creates excessive load on Prometheus and targets |

The principle isn't "15s is always right" — it's that the interval must be short enough for dashboards to be meaningful, alerting to fire in time, and short-lived spikes to be caught. 600s fails all three tests.

---

#### Bug 2 — Wrong port for app targets

**Why does this happen?** Port 9090 is where *Prometheus itself* listens — not where your application containers listen. The app containers listen on port 8080. When Prometheus tries to connect to port 9090 on an app container, nothing is listening there, so the connection is refused.

**How do you know the correct port?** Two sources confirmed it before you opened the config:
- `docker compose ps` showed `->8080/tcp` for both app containers
- The error message itself showed the wrong port in the failed URL

---

#### Bug 3 — Wrong metrics path

**Why does this happen?** Prometheus sends an HTTP GET to a specific path on the target. `/api/metrics` doesn't exist on these apps — so the server returns 404 and Prometheus marks the target as DOWN.

**How do you find the correct path?** Three approaches in order of preference:

**1. Probe the running container directly:**
```bash
docker compose exec app1 curl -s http://localhost:8080/metrics | head -5
```

| Part | What it does |
|---|---|
| `docker compose exec app1` | Runs a command inside the running `app1` container |
| `curl -s http://localhost:8080/metrics` | Makes an HTTP request to port 8080 on the `/metrics` path from inside the container |
| `\| head -5` | Shows only the first 5 lines — enough to confirm it's returning Prometheus-format metrics |

If you get metric output back, that's your path. If you get a 404, try other common paths.

**2. Know the convention:**

| Path | Framework |
|---|---|
| `/metrics` | Default for all Prometheus client libraries — always your first guess |
| `/actuator/prometheus` | Java Spring Boot |
| `/actuator/metrics` | Spring Boot variant |
| `/prometheus/metrics` | Some custom setups |

**3. Check the application documentation or README** — if someone wrote the app, they should have documented what endpoint it exposes.

---

#### Bug 4 — Hostname typo for node exporter

**Why does this happen?** In Docker Compose, each service's name becomes a DNS hostname that other containers use to reach it. Docker's internal DNS is exact-match — `node-exporter` and `node_exporter` are two completely different hostnames. The config uses an underscore; the service is defined with a hyphen.

**How do you confirm the correct name?** `docker compose ps` already showed you — the SERVICE column listed `node-exporter` with a hyphen. Always copy the service name directly from `docker compose ps` or `docker-compose.yml` rather than typing it from memory.

---

### Step 5: Apply all four fixes

Open the config file:

```bash
vi prometheus.yml
```

Apply each fix:

**Fix 1 — Scrape interval:**
```yaml
# Change from:
global:
  scrape_interval: 600s
  evaluation_interval: 600s

# Change to:
global:
  scrape_interval: 15s
  evaluation_interval: 15s
```

**Fix 2 & 3 — App targets port and path:**
```yaml
# Change from:
- job_name: 'app'
  static_configs:
    - targets: ['app1:9090', 'app2:9090']
  metrics_path: '/api/metrics'

# Change to:
- job_name: 'app'
  metrics_path: '/metrics'
  static_configs:
    - targets: ['app1:8080', 'app2:8080']
```

**Fix 4 — Node exporter hostname:**
```yaml
# Change from:
- job_name: 'node'
  static_configs:
    - targets: ['node_exporter:9100']

# Change to:
- job_name: 'node'
  static_configs:
    - targets: ['node-exporter:9100']
```

**The complete fixed prometheus.yml:**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'app'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['app1:8080', 'app2:8080']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

---

### Step 6: Restart Prometheus and validate

Editing `prometheus.yml` has no effect until Prometheus reloads it. In this lab, restart the container:

```bash
docker compose restart prometheus
```

| Part | What it does |
|---|---|
| `docker compose restart` | Stops and starts the named service, picking up any config file changes |
| `prometheus` | The service name as defined in `docker-compose.yml` |

> **In production:** You wouldn't restart Prometheus — that creates a gap in metric collection. Instead you'd send a reload signal: `kill -HUP <pid>` or POST to the `/-/reload` endpoint. This reloads the config without stopping the process.

Wait for Prometheus to initialise and complete its first scrape:

```bash
sleep 30
```

Then re-run the targets check:

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E "health|lastError|job"
```

All three jobs should now show `"health": "up"` with empty `lastError` fields.

---

### Step 7: Run the validator

```bash
./tools/labrunner.sh validate monitoring-labs/lab-055-prometheus-scraping-broken
```

Expected output:
```
✅  Prometheus is healthy
✅  All 3 targets are UP
✅  Scrape interval is reasonable (10-60s)
✅  Metrics path is correct (/metrics)
✅  Metrics are being collected (up metric has data)
Results: 5 passed, 0 failed
```

---

## Docker Lab vs Real Life

- **Browser access:** In a real environment with browser access you'd open `http://<host>:9090/targets` directly — much faster than the API command. In this lab you're SSHd into a headless Pi, so the API command is the correct approach.
- **Config reload without restart:** Production Prometheus uses `kill -HUP` or the `/-/reload` HTTP endpoint to reload config without stopping. Restarting creates a gap in data collection.
- **Service discovery:** Production Prometheus doesn't use static target lists. It uses service discovery — Kubernetes SD, EC2 SD, Consul SD — so new pods or instances are automatically picked up without editing config files.
- **Relabeling:** `relabel_configs` lets you transform or filter targets dynamically — only scraping pods with a specific annotation, or rewriting job labels based on discovered tags.
- **Recording rules:** Pre-compute expensive PromQL queries and store the result as a new metric. Keeps dashboards fast at scale without recalculating on every load.
- **Remote write:** Production Prometheus writes to long-term storage backends (Thanos, Mimir, Grafana Cloud) because local disk retention is limited.

---

## Key Concepts to Take Away

- **The targets page is your first stop** — Prometheus tells you exactly why each target is failing. Read the error message before touching any config.
- **Only 3 of 4 bugs produce error messages** — the scrape interval bug is silent. You'd only catch it by inspecting the config or noticing sparse dashboard data.
- **`docker compose ps` gives you the correct ports before you open any config file** — the internal port (right side of `->`) is what Prometheus needs.
- **`/metrics` is the default path** — verify against the running container if unsure. Never assume.
- **Docker Compose service names are DNS hostnames** — exact character match. Copy from `docker compose ps`, don't type from memory.
- **15s is the standard default** — but 30-60s is common in production. The interval must be short enough for meaningful dashboards, timely alerting, and catching short-lived spikes.
- **Config changes require a restart or reload** — editing the file has no effect until Prometheus picks it up.

---

## Common Mistakes

- **Pointing app targets at port 9090** — that's Prometheus's own port, not your application's. Always check `docker compose ps` first.
- **Guessing the metrics path** — always verify by probing the container directly with `docker compose exec`.
- **Underscore vs hyphen in hostnames** — Docker DNS is exact-match. Copy the name, don't type it.
- **Forgetting to restart** — editing `prometheus.yml` and wondering why nothing changed.
- **Scrape interval too short** — 1s creates enormous load and storage use. 15-30s is the practical sweet spot.

---

## Cleanup / Reset

To reset the lab to its broken starting state so it can be run again from Step 0:

```bash
docker compose down
git checkout prometheus.yml
docker compose up -d
```

| Command | What it does |
|---|---|
| `docker compose down` | Stops and removes all containers defined in `docker-compose.yml` |
| `git checkout prometheus.yml` | Restores `prometheus.yml` to the broken version committed in the repo |
| `docker compose up -d` | Starts all containers in detached mode (background) |

You can now run the lab from Step 0 with a clean broken state.
