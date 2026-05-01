# Solution Walkthrough — Lab 056: Grafana Dashboard Broken

> **Scenario you're stepping into:** You've picked up `INCIDENT-MON-007`. The new Application Dashboard was deployed overnight. Grafana is up, the dashboard is supposedly provisioned, but the product team is reporting nothing's appearing on screen. Prometheus is reportedly scraping the app fine. The dashboard's author is on holiday for a week. You don't know what's broken — that's what you have to figure out.

---

## TLDR (Plain English)

There are **five separate bugs** spread across three layers — Grafana provisioning, Grafana ↔ Prometheus connectivity, and the dashboard's PromQL queries. They're independent: fixing one doesn't fix the others.

In plain terms:

1. **The dashboard JSON file is in the wrong format**, so Grafana refuses to load it. The dashboard never even appears in Grafana — that's why the product team sees nothing. (Bug 6 in this walkthrough; we found it first.)
2. **Grafana doesn't know where Prometheus is.** It's been told "Prometheus is on this same machine as me," but inside Docker, that's not true. We need to give Grafana the correct address. (Bug 1.)
3. **One panel uses a function that doesn't exist** (`rates` — there's no such thing; the real one is `rate`). (Bug 2.)
4. **Another panel asks for the "95th percentile" but types it as `95` instead of `0.95`.** Prometheus expects a fraction, not a percentage, and silently returns infinity. (Bug 4.)
5. **The last panel asks for a metric called `active_connection`** (singular), but the app actually publishes it as `active_connections` (plural). One letter off, no result. (Bug 5.)

> **A note on Bug 3:** The original lab brief listed a sixth bug — single quotes in a label matcher. **It's not a bug.** PromQL accepts single quotes, double quotes, and backticks as equivalent string literals. The Error Rate panel in the broken state uses single quotes and works correctly. We do not change it.

**The diagnostic sequence that solves this lab:**

The system tells you what's wrong if you ask the right questions. Every layer has a way to talk back:

1. Read the Grafana logs first — that's where Bug 6 announces itself
2. Test the data source with Grafana's "Save & Test" button (or its API) — that exposes Bug 1
3. Run each panel's query directly in Prometheus's expression browser — that exposes Bugs 2, 4, 5

The mindset: **the answer is in the running system, not in the source files.** Open files only when the running system has told you which file to open, and what to look for.

---

## Phase 1 — Triage: Is the stack even up?

The ticket says Grafana is up and Prometheus is scraping. Don't trust 3am ticket comments — see for yourself.

```bash
cd ~/cloud-engineer-labs/monitoring-labs/lab-056-grafana-dashboard-broken
docker compose ps
```

| Component | Meaning |
|---|---|
| `docker compose ps` | List the containers managed by `docker-compose.yml` in this directory, plus their status |

Three services should be `Up`: `prometheus`, `grafana`, `app`. If any are down, bring them up:

```bash
docker compose up -d
```

| Component | Meaning |
|---|---|
| `docker compose up` | Start the services defined in `docker-compose.yml` |
| `-d` | Detached — run in the background, return the prompt |

Confirm each component is alive:

```bash
curl -s http://localhost:3000/api/health
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:8080/metrics | head -20
```

| Component | Meaning |
|---|---|
| `curl -s` | Make an HTTP request, suppress the progress bar |
| `/api/health` | Grafana's built-in health endpoint — returns JSON with `database: ok` |
| `/-/healthy` | Prometheus health endpoint — returns "Prometheus Server is Healthy" |
| `/metrics` | The application's Prometheus metrics endpoint |
| `head -20` | Limit output to the first 20 lines |

**A small thing worth knowing:** the first chunk of any `prometheus_client`-based `/metrics` endpoint is automatic Python runtime metrics (`python_gc_*`, `python_info`, `process_*`). The application's own metrics come further down. If you don't see `http_requests_total` in the first 20 lines, that's not a problem — it's noise.

If everything's healthy, the stack is alive. Now we move from "is anything broken at the infrastructure layer?" to "why is the *behaviour* wrong?"

---

## Phase 2 — First look at Grafana

Open Grafana in a browser:

```
http://<pi-ip>:3000
```

(Find the Pi's IP with `hostname -I` on the Pi, or use `localhost` if you're browsing on the Pi itself.)

Anonymous viewing is enabled by Compose env (`GF_AUTH_ANONYMOUS_ENABLED=true`), so dashboards are browsable without logging in. For admin actions later we log in with `admin` / `admin`.

Navigate: **Dashboards**.

**Surprise.** The dashboards list is empty. There's no "Application Dashboard" here. Just "Shared with me" (Grafana's built-in folder).

Stop. This isn't the symptom we expected.

The ticket said the dashboard was "provisioned but showing nothing on the screen as expected." That suggested *empty panels*. But the dashboard isn't here at all. **That's a different problem.**

### Diagnostic pathway — what could cause this?

| Possibility | How we'd know |
|---|---|
| (a) The provisioning **provider** isn't configured at all | `provisioning/dashboards/dashboards.yml` is missing or malformed |
| (b) Grafana's provisioning ran but **rejected** the dashboard JSON | We'd see errors in the Grafana container logs |
| (c) The volume mount isn't working — the file isn't where Grafana expects | We'd verify by `docker exec` into the container |
| (d) The dashboard JSON is malformed in some way | Logs again |

The cheapest check is **read the logs**. Grafana announces what it's doing during startup, including provisioning. Errors land there.

---

## Phase 3 — Read the logs (this is where Bug 6 is hiding)

```bash
docker compose logs grafana --tail 200 | grep -E "level=(error|warn)"
```

| Component | Meaning |
|---|---|
| `docker compose logs grafana` | Print everything Grafana has written to stdout/stderr |
| `--tail 200` | Look back 200 lines so we capture the early-startup provisioning step |
| `\|` (pipe) | Send the output to the next command |
| `grep -E "level=(error\|warn)"` | Filter to lines Grafana itself flagged as error or warning. `-E` enables extended regex so `\|` works as "or". |

**This is the diagnostic move you should make in any "thing not behaving as expected" investigation.** Most production tools log their errors at startup. If something didn't work, the system probably already told you why — you just have to look.

In our run, the smoking-gun line is this:

```
logger=provisioning.dashboard
type=file name=default
level=error
msg="failed to load dashboard from "
file=/etc/grafana/provisioning/dashboards/app-dashboard.json
error="Dashboard title cannot be empty"
```

### Diagnostic pathway for Bug 6

1. **The error says "Dashboard title cannot be empty".** I can see the title is set in the JSON file (`"title": "Application Dashboard"`). So either Grafana is reading a different file, or it's reading the title from somewhere different to where I think it is.

2. **Look at the JSON structure carefully:**

   ```json
   {
     "dashboard": {
       "title": "Application Dashboard",
       ...
     }
   }
   ```

   The whole dashboard is wrapped in an outer `{ "dashboard": { ... } }` key.

3. **Why does that matter?** That wrapping format is Grafana's **HTTP API import format** — the shape you'd POST to `/api/dashboards/db` over HTTP. The provisioning system, on the other hand, expects the dashboard fields **at the top level of the file** — no outer `dashboard` wrapper.

4. **So when Grafana's provisioner reads this file, it looks for `title` at the top level, finds nothing, and reports "title cannot be empty".** It never even gets to looking inside the `dashboard:` key.

5. **The fix:** unwrap the JSON. The contents of the `dashboard` key need to *be* the file.

This is a really common gotcha — people copy a dashboard out of the Grafana UI's "Export JSON" feature (which gives you the API-import format) and paste it into provisioning, and it silently fails to load. Exact failure mode here.

### Apply Fix 6

Edit `provisioning/dashboards/app-dashboard.json`. The current top of the file looks like this:

```json
{
  "dashboard": {
    "title": "Application Dashboard",
    "panels": [ ... ],
    ...
  }
}
```

It needs to become:

```json
{
  "title": "Application Dashboard",
  "panels": [ ... ],
  ...
}
```

Two changes:
1. Delete the second line (`"dashboard": {`)
2. Delete the matching closing `}` at the bottom of the file

Then restart Grafana so it re-runs provisioning:

```bash
docker compose restart grafana && sleep 10
```

| Component | Meaning |
|---|---|
| `docker compose restart grafana` | Stop and start just the Grafana service. Provisioning re-runs on container start. |
| `&&` | Run the next command only if the previous succeeded |
| `sleep 10` | Give Grafana ten seconds to come back up |

Verify the error is gone:

```bash
docker compose logs grafana --since 30s | grep -E "level=(error|warn)"
```

| Component | Meaning |
|---|---|
| `--since 30s` | Only show log lines from the last 30 seconds — i.e. since the restart |

Expected: no output, or only unrelated background warnings (e.g. an `elasticsearch` plugin warning, unrelated to our lab). The dashboard provisioning error from before is gone.

Refresh the browser. **Application Dashboard** now appears in the dashboards list. Open it. Now we see the symptom the ticket actually described — four panels, all "No data".

---

## Phase 4 — First look at the dashboard panels

The dashboard renders. Four panels, four "No data" messages. **But look closely** — each panel has a small warning triangle next to its title.

That triangle is information, not noise. It distinguishes between two kinds of "No data":

| Panel state | What it likely means |
|---|---|
| "No data" + warning triangle | The query was *attempted* but failed (parse error, unreachable data source, etc.) |
| "No data" + no icon | The query ran successfully but returned an empty result set |
| Spinner that never resolves | Data source unreachable, request hanging |

**Hover over any warning triangle.** A tooltip appears with the actual error Grafana saw when running that query. That's diagnostic gold.

In this run, hovering produced:

```
Post "http://localhost:9090/api/v1/query_range":
dial tcp [::1]:9090: connect: connection refused
```

### Reading the error in detail

| Part | What it means |
|---|---|
| `Post "http://localhost:9090/api/v1/query_range"` | Grafana tried to make an HTTP POST to this URL — i.e. it's reading `http://localhost:9090` from its data source config |
| `dial tcp [::1]:9090` | "Dial" = open a TCP connection. `[::1]` is IPv6 loopback — the same as `127.0.0.1` in IPv4. Means "this same machine I'm running on." |
| `connect: connection refused` | The OS tried to connect, got an immediate refusal — meaning the machine is reachable, but nothing is listening on port 9090 there |

**"Connection refused" is a specific signal worth knowing.** It means the network is fine, the machine is reachable, but the port is empty. It's a *fast* failure — milliseconds, not seconds. Compare:

| Error type | What the OS is telling you |
|---|---|
| **Connection refused** | "I reached the machine, but nothing is listening on that port" — fast |
| **Connection timed out** | "I tried to reach the machine and never got a response" — slow (30+ seconds) |
| **No such host / unknown host** | "I couldn't even resolve that hostname to an IP" — DNS problem |
| **Network unreachable** | "I can't even route to that network" — routing problem |

The fast-refusal here means **something went wrong with the address Grafana is using, not with the network**.

### Pulling that error from the CLI instead of the UI

Tooltips are fine when you're in front of the screen, but you can't grep them, paste them into a ticket, or include them in scripts. Grafana exposes the same probe via API:

```bash
DS_UID=$(curl -s -u admin:admin http://localhost:3000/api/datasources \
  | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['uid'])")

curl -s -u admin:admin "http://localhost:3000/api/datasources/uid/${DS_UID}/health" \
  | python3 -m json.tool
```

| Component | Meaning |
|---|---|
| `DS_UID=$(...)` | Bash command substitution — capture the inner command's stdout into a variable |
| `python3 -c "..."` | Inline Python script — cleaner than parsing JSON with grep/sed |
| `json.load(sys.stdin)[0]['uid']` | Read JSON from stdin, take the first element, return its `uid` |
| `/api/datasources/uid/{uid}/health` | Modern Grafana data source health endpoint (Grafana 13+). The older name-based endpoint (`/api/datasources/name/.../health`) is deprecated and returns 404. |

This returns the exact same diagnostic the UI tooltip showed, machine-readable. **Pattern worth remembering: anything a UI knows, an API knows. Find the API and you're free of dependency on hovering.**

### Proving the diagnosis from inside the container

We can also verify causally — show what `localhost:9090` actually resolves to from where Grafana is, vs from the Pi:

```bash
# From the Pi's host network:
curl -sf http://localhost:9090/-/healthy
# → "Prometheus Server is Healthy."

# From inside the Grafana container:
docker exec lab056-grafana wget -qO- http://localhost:9090/-/healthy 2>&1
# → "wget: can't connect to remote host: Connection refused"

docker exec lab056-grafana wget -qO- http://prometheus:9090/-/healthy 2>&1
# → "Prometheus Server is Healthy."
```

| Component | Meaning |
|---|---|
| `docker exec <container> <command>` | Run a command inside a running container's filesystem and network namespace |
| `wget -qO-` | Quietly fetch a URL and dump the body to stdout. We use `wget` because the Grafana image doesn't have `curl` installed by default. |
| `2>&1` | Redirect stderr to stdout so we capture error messages too |

**Same URL, three different machines, three different answers** — that's the entire lesson of Bug 1 demonstrated in three commands.

---

## Phase 5 — Bug 1: `localhost` vs `prometheus`

### Conceptual diagnosis

The data source is configured in `provisioning/datasources/prometheus.yml`. The current state:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
```

Reading line by line:

| Field | Meaning |
|---|---|
| `apiVersion: 1` | Version of Grafana's provisioning schema |
| `name: Prometheus` | Display name in the Grafana UI. Not a hostname — just a label. |
| `type: prometheus` | The driver. Tells Grafana to use its built-in Prometheus plugin. |
| `access: proxy` | Grafana's *backend* makes the request to Prometheus, not the user's browser. (The alternative, `direct`, is deprecated.) |
| `url: http://localhost:9090` | The address used in those backend requests **— interpreted from the Grafana container's perspective.** |
| `isDefault: true` | Used by panels that don't specify a data source |
| `editable: true` | Allows the data source to be edited via the UI |

**The crux: because `access: proxy`, the URL is read from inside the Grafana container.** When the dashboard loads:

1. Your browser makes a request to **Grafana**
2. Grafana then makes its own request to **Prometheus**, server-to-server
3. Grafana passes the result back to your browser

Step 2 is where `url:` is used. From inside the Grafana container, `localhost` means *the Grafana container itself* — not the Pi, not Prometheus.

Each Docker container has its own private network namespace, with its own loopback interface and its own concept of `localhost`. Two containers running on the same host **do not share localhost**.

What's actually running on port 9090 from each viewpoint?

| Where you are | What `localhost` means there | What's on port 9090 there |
|---|---|---|
| The Pi's host shell | The Pi | Yes — Prometheus, via the port mapping `9090:9090` |
| The Prometheus container | The Prometheus container | Yes — Prometheus itself |
| **The Grafana container** | **The Grafana container** | **Nothing — Grafana is on 3000, not 9090** ❌ |

So Grafana is *trying to pull Prometheus from itself*, and itself doesn't run Prometheus. Connection refused.

### How containers actually reach each other in Docker Compose

Compose creates an internal network for the project. Every service in `docker-compose.yml` is registered on that network as a DNS hostname using its **service name** (the top-level key under `services:`):

```yaml
services:
  prometheus:    # ← becomes a DNS hostname on the Compose network
    ...
  grafana:       # ← also a hostname
    ...
  app:           # ← also a hostname
    ...
```

From any container in the project, `prometheus` resolves to the Prometheus container's IP. `grafana` resolves to Grafana. `app` resolves to the app. **Forget about IP addresses — they change between restarts. Use service names.**

So `http://prometheus:9090` from inside the Grafana container means "go to the container named `prometheus` on this Compose network, port 9090." That works.

### Apply Fix 1

Edit `provisioning/datasources/prometheus.yml`:

```yaml
# Before
url: http://localhost:9090

# After
url: http://prometheus:9090
```

Restart Grafana (provisioning files are read on container start):

```bash
docker compose restart grafana && sleep 10
```

Re-run the health probe:

```bash
DS_UID=$(curl -s -u admin:admin http://localhost:3000/api/datasources \
  | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['uid'])")

curl -s -u admin:admin "http://localhost:3000/api/datasources/uid/${DS_UID}/health" \
  | python3 -m json.tool
```

Expected: `"status": "OK"` and `"message": "Successfully queried the Prometheus API."`. Bug 1 done.

---

## Phase 6 — Bug 1 fixed but the panels still fail (in different ways)

Reload the dashboard. **The panels' behaviour changes informatively.** This is the diagnostic moment where we sort the remaining bugs into their categories:

| Panel | What you see | What it tells us |
|---|---|---|
| **Request Rate** | "No data" + warning triangle | The query was attempted, errored — likely a parse error or unknown function |
| **Error Rate (%)** | A number renders (e.g. 8.96%) | The query ran successfully and returned a value. **Working.** |
| **Request Duration (p95)** | Graph axes render but values are flat / unreadable | The query ran, returned something, but the value is garbage |
| **Active Connections** | "No data" + **no triangle** | The query ran successfully but returned an empty result set |

**Four different categories of failure on one screen.** This is worth absorbing because it generalises:

- **Loud failures** (parse errors) → Grafana shows a warning triangle, tooltip gives the exact error
- **Working** → renders a value, but **don't assume that means correct** — the value still has to be sanity-checked
- **Silent garbage** → renders something useless, no warning anywhere on the dashboard
- **Silent empty** → "No data" with no warning at all

Each needs a different diagnostic move. We deal with the loud one first because it's the cheapest to investigate.

---

## Phase 7 — Diagnose each remaining query directly in Prometheus

The technique: open Prometheus's expression browser (`http://<pi-ip>:9090/graph`) and paste each panel's query in. **Prometheus will tell you exactly what it thinks of the query** — much more clearly than Grafana does. This is the most useful single skill in PromQL debugging.

### Bug 2: Request Rate — `rates(http_requests_total[5m])`

Pasting this into the expression browser produces:

```
Error executing query
invalid parameter "query": 1:1: parse error: unknown function with name "rates"
```

**Diagnostic pathway:**

1. Prometheus is telling me directly: there's no function called `rates`. So either it's a typo or it's a function from a different system.
2. Do I know the right one? PromQL's standard function for "rate of change of a counter over time" is `rate()` — singular. Counters tick up; `rate()` smooths them into a per-second figure over a window.
3. Try `rate(http_requests_total[5m])` in the expression browser. It returns numbers. Confirmed.

**What `rate()` actually does:**

Most metrics in real systems are **counters** — values that only ever go up (total requests served, total bytes transferred, total errors). Counters aren't useful raw — knowing your service has served 47,283,991 requests since the last reboot tells you nothing actionable. What you want is the **per-second rate of increase**.

`rate(http_requests_total[5m])`:

| Part | Meaning |
|---|---|
| `http_requests_total` | The counter metric |
| `[5m]` | Range vector — sample over the last 5 minutes |
| `rate(...)` | Compute the difference between the start and end of the window, divide by window length in seconds |

If the counter went from 100,000 to 130,000 over 5 minutes (300 seconds), `rate()` returns `(130000 − 100000) / 300 = 100` requests per second.

**There is no plural form** — `rate()` already returns a value per series.

### Apply Fix 2

In the dashboard JSON, change `rates(` to `rate(` in panel 1:

```json
"expr": "rate(http_requests_total[5m])"
```

### Bug 3 candidate: Error Rate — *not actually a bug*

The Error Rate panel uses `status='500'` with single quotes. The original lab brief flagged this as a syntax error.

Paste it directly into Prometheus:

```
sum(rate(http_requests_total{status='500'}[5m])) / sum(rate(http_requests_total[5m])) * 100
```

Result: `0.4157173333333334`. **No error.** The panel was already showing a valid value.

Per the official Prometheus documentation: *string literals in PromQL can be in single quotes, double quotes, or backticks*. All three are valid syntax with the same Go-style escaping rules. The single-quote "bug" is not a bug.

**The lesson:** always verify a "bug" is actually a bug by reproducing it against the engine itself. Documentation and team folklore both go stale; running the query is the source of truth. **Don't trust style preferences as syntax requirements.**

### Apply Fix 3

**No change.** Leave the Error Rate panel as it is.

### Bug 4: Request Duration (p95) — `histogram_quantile(95, ...)`

Paste it into Prometheus:

```
histogram_quantile(95, rate(http_request_duration_seconds_bucket[5m]))
```

Prometheus returns:

> **Query warning** — PromQL warning: quantile value should be between 0 and 1, got 95
>
> Result: `{instance="app:8080", job="app"} → +Inf`

**Two things at once:**

- The query **succeeds** (yellow warning, not red error)
- Prometheus **explicitly tells you** the value is wrong: "quantile value should be between 0 and 1, got 95"
- The actual returned value is **+Inf** — infinity

**This is the silent-garbage failure class — the most dangerous kind.** A query that *runs* but is meaningless. There's no error to catch in your alerting; the query passes "the query works" tests; the result is just wrong.

**And critically: Grafana hides this warning.** On the dashboard you just see a flat empty graph. The warning Prometheus emitted gets swallowed somewhere between Prometheus's API response and Grafana's panel rendering. The only way to see it is to do exactly what we just did — copy the query into Prometheus and run it directly.

> **General lesson:** Prometheus's expression browser is more honest than Grafana's panels. When a panel looks wrong, run its query in Prometheus.

**What histograms and quantiles are:**

Histograms in Prometheus measure things with a *distribution*, not a single value. Take HTTP request duration: most requests are fast (a few ms), some are slow (a few hundred ms), a few are very slow (multiple seconds). The *average* duration is misleading because outliers skew it.

Instead, the application records each request's duration into **buckets**:

```
duration ≤ 0.005s  : 4,251 requests
duration ≤ 0.01s   : 4,890 requests
duration ≤ 0.025s  : 5,103 requests
...
duration ≤ 2.5s    : 9,847 requests
```

`histogram_quantile(0.95, ...)` walks the buckets, finds where the 95% line crosses, and interpolates a duration. The first argument is the **fraction** between 0 and 1:

- `0.5` = 50th percentile (median)
- `0.95` = p95
- `0.99` = p99

Why fraction not percentage? Many PromQL functions use 0-1 ranges (e.g. `topk`); quantiles are mathematical objects defined over [0, 1]. The "p95" notation is human shorthand.

> **Histogram bucket gotcha worth knowing:** `histogram_quantile()` is an *approximation*, accurate only to the resolution of the buckets. The default Python client buckets jump from 1.0 to 2.5, with no boundary in between. If your real durations top out at 2.0, your p95 reading might come out as 2.35 — not because requests are taking that long, but because the function is interpolating within the 1.0-2.5 bucket. For accurate quantiles you need fine-grained buckets *covering the range you care about*.

### Apply Fix 4

Change `95` to `0.95` in the dashboard JSON:

```json
"expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
```

### Bug 5: Active Connections — `active_connection`

Paste it into Prometheus:

```
active_connection
```

Result: **Empty query result. This query returned no data.**

No error. No warning. Just nothing.

**Diagnostic pathway:**

1. No parse error means the query is syntactically valid PromQL.
2. Empty result means no series in Prometheus has that name.
3. Empty results don't error — Prometheus treats "metric doesn't exist" as a valid empty result. Typos are very easy to miss.
4. Check what metrics Prometheus actually has:

   ```bash
   curl -s http://localhost:9090/api/v1/label/__name__/values | grep -i connection
   ```

   | Component | Meaning |
   |---|---|
   | `/api/v1/label/__name__/values` | Prometheus API endpoint that lists every distinct value of the special label `__name__` — i.e. every metric name Prometheus knows about |

   Output: `active_connections` (plural).

5. Confirm in `app.py`:

   ```bash
   grep -i connection app.py
   ```

   Output:

   ```python
   ACTIVE_CONNECTIONS = Gauge('active_connections', 'Active connections')
   ```

   The app exposes the metric as plural. The query uses singular. That's the bug.

**Why this bug is the most insidious in the lab:**

- No error message anywhere
- No warning indicator on the panel
- The bug is one letter — easy to introduce, easy to miss in code review
- Prometheus has no fuzzy matching. `active_connection` and `active_connections` are entirely unrelated identifiers as far as the engine is concerned

**Habits that catch this in real life:**

| Habit | Why it helps |
|---|---|
| Always test a query in Prometheus first before pasting into Grafana | Empty result there = bug, not "data not arriving" |
| List all available metrics with `/api/v1/label/__name__/values` | Quickly catch typos by visually scanning what *does* exist |
| Use a PromQL-aware editor with autocomplete (PromLens, VS Code with the right extension) | Prevents typos at write-time |
| For critical dashboards, write a unit test asserting each panel's query returns ≥ 1 series | Catches the bug at deploy-time, not at outage-time |

### Apply Fix 5

```json
"expr": "active_connections"
```

---

## Phase 8 — Reload and verify

Restart Grafana so it picks up the dashboard JSON changes:

```bash
docker compose restart grafana && sleep 10
```

Verify no new errors:

```bash
docker compose logs grafana --since 30s | grep -E "level=(error|warn)"
```

Reload the dashboard. All four panels should now render meaningful data:

| Panel | Expected |
|---|---|
| Request Rate | Multiple lines (one per `(method, status)` pair, e.g. `GET 200` and `GET 500`), small per-second values |
| Error Rate (%) | A single number around 8-10% (matching the simulated traffic mix) |
| Request Duration (p95) | A small floating-point value, around 1.8-2.4 seconds (subject to the histogram bucket caveat above) |
| Active Connections | A gauge between 5 and 50, jumping around |

No warning triangles on any panel.

Run the validator:

```bash
lab validate monitoring-labs/lab-056-grafana-dashboard-broken
```

Expected: 12/12 passing.

---

## Phase 9 — Cleanup / reset

Containers are disposable, no special reset needed. To return to the broken starting state:

```bash
git checkout -- provisioning/datasources/prometheus.yml
git checkout -- provisioning/dashboards/app-dashboard.json
docker compose restart grafana
```

| Component | Meaning |
|---|---|
| `git checkout -- <file>` | Restore a file to its committed state, discarding local changes. The `--` is a path/branch separator. |

To tear down completely:

```bash
docker compose down
```

| Component | Meaning |
|---|---|
| `docker compose down` | Stop and remove the containers, networks, and default volumes for this Compose project |

---

## Sidenote — Pi clock skew

If you saw a "Server time is out of sync" banner in Prometheus's UI during the run, your Pi's clock has drifted from network time. Pis don't have a hardware real-time clock by default and depend on NTP for accurate time. Drift causes weird and *misleading* monitoring symptoms — alerts firing at wrong times, queries returning wrong-window data.

Fix:

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
timedatectl status
```

Look for `System clock synchronized: yes`. Not part of the lab fix, but worth doing on any Pi that runs monitoring.

---

## Docker Lab vs Real Life

- **Dashboard-as-code:** Production teams version-control dashboards in Git and provision them via Terraform's Grafana provider, the Grafana HTTP API, or Grafonnet. Hand-editing JSON is error-prone — this lab is a microcosm of why.
- **Dashboard variables (templating):** Real dashboards use template variables (dropdowns) for environment, service, instance — one dashboard works across all environments.
- **Annotations:** Production dashboards overlay deployment markers, incident timestamps, and config changes onto the graphs.
- **Alert rules:** Modern Grafana defines alerts alongside panels. Many teams prefer Prometheus's own Alertmanager for routing.
- **Datasource URL is environment-dependent:** In Kubernetes, the URL would be `http://prometheus.monitoring.svc.cluster.local:9090` (Kubernetes Service DNS). In Docker Compose it's the service name. In managed Grafana Cloud it's an external URL with auth. Same concept; different DNS context.
- **Grafana 13 API surface:** The data source health endpoint `/api/datasources/name/.../health` is deprecated. Grafana 13+ uses UID-based addressing. If you're scripting against Grafana, lookups by name are ageing badly.
- **Histogram bucket selection is a design decision.** Default buckets are rarely the right choice for production — design buckets around the latencies you care about.

---

## Key Concepts Learned

- **`localhost` inside a container means the container itself.** Always use the Docker Compose service name (or Kubernetes Service DNS name) when one container needs to reach another. The single most common Compose mistake.
- **Read the logs first.** When a system isn't behaving as expected, the system has usually already told you why. Bug 6 in this lab can only be diagnosed by reading the Grafana logs — there's no UI clue.
- **Grafana is a window, not a warehouse.** It doesn't have its own query language. PromQL belongs to Prometheus; Grafana is a courier.
- **Prometheus's expression browser is more honest than Grafana's panels.** When a panel looks wrong, run its query in Prometheus directly. You'll see warnings and errors that Grafana hides.
- **PromQL string literals can be single, double, or backtick quoted.** All three are valid. The single-quote "bug" was a documentation error.
- **`histogram_quantile()` takes a fraction (0-1), not a percentage.** Returns infinity if you give it a number above 1, with a warning that Grafana doesn't display.
- **Prometheus does not error on non-existent metric names.** Typos return empty results silently.
- **"Runs without error" ≠ "correct".** Always sanity-check the actual value a query returns.
- **The Grafana provisioning format is a flat object, not the API-import wrapper.** Copy-pasting from the UI's "Export JSON" produces invalid provisioning files.
- **Validators that grep JSON are validators that lie.** Field order isn't stable. Use a real JSON parser (`jq`, or `python3 -c '...'`).

---

## Common Mistakes & Gotchas

- **Treating "No data" as one symptom.** It can mean broken provisioning, broken connectivity, broken queries, or missing metrics. Different diagnostic moves for each. The warning triangle on a panel is a category indicator — heed it.
- **Editing provisioned dashboards in the Grafana UI.** Changes are lost on the next provisioning run (i.e. on Grafana restart). For provisioned dashboards, edit the source files and re-provision.
- **Forgetting that Grafana provisioning is read on container start, not on file change.** Edit the file, then *restart Grafana*. No restart, no effect.
- **Confusing the API-import wrapper with the provisioning format.** Watch for the leading `{ "dashboard": { ... } }` wrapper.
- **Trusting the ticket's diagnosis.** The ticket here said "Prometheus is collecting metrics fine" — and that turned out to be true. But on a different ticket the assumption could be wrong. Always re-confirm upstream before working on downstream.
- **Hovering over UI tooltips when you should be calling APIs.** Anything the UI knows, the API knows. The API is grep-able, scriptable, and auditable.
- **Grepping JSON.** Field order is unstable. Use a real parser.
