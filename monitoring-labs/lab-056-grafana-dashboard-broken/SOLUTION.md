# Solution Walkthrough — Lab 056: Grafana Dashboard Broken

> **Scenario you're stepping into:** You've picked up `INCIDENT-MON-007`. The new Application Dashboard was deployed overnight. Grafana is up and the dashboard is provisioned, but every panel shows "No data". Prometheus is reportedly scraping the app fine. The dashboard's author is on holiday for a week. You don't know what's broken — that's what you have to figure out.

---

## TLDR (Plain English)

The dashboard is empty because **five separate things are broken** between Grafana, Prometheus, and the dashboard's queries. They're independent of each other — fixing one doesn't fix the others.

In plain terms:

1. **Grafana doesn't know where Prometheus is.** It's been told "Prometheus is on this same machine as me," but inside Docker, that's not true — Prometheus is in a different container. We need to give Grafana the correct address.
2. **One panel is using a function that doesn't exist** (`rates` — there's no such thing; the real one is `rate`).
3. **Another panel is using the wrong type of quote marks** in its query — Prometheus is strict about quotes.
4. **Another panel is asking for the "95th percentile" but typing it as `95` instead of `0.95`.** Prometheus expects a fraction, not a percentage.
5. **The last panel is asking for a metric called `active_connection`** (singular), but the app actually publishes it as `active_connections` (plural). One letter off, no result.

**The fix sequence:** Use the running services themselves to diagnose. Confirm metrics exist (Prometheus UI). Test the data source (Grafana's "Save & Test" button). Test each query in isolation (Prometheus's expression browser). Apply the five fixes. Restart Grafana. Re-validate.

The mindset for this kind of incident: **the answer is in the running system, not in the source files.** Use the tools to ask "is this layer working?" before opening any code.

---

## Phase 1 — Triage: Is the stack even up?

I've just been assigned the ticket. Before I start theorising, I want to know what state the world is actually in. The ticket says Grafana is up and Prometheus is scraping — but I'd rather see for myself than trust a 3am ticket comment.

**The questions in my head:**

- Are all three containers running?
- Are they healthy?
- Is anything in the logs that looks like a smoking gun?

```bash
cd ~/cloud-engineer-labs/monitoring-labs/lab-056-grafana-dashboard-broken
docker compose ps
```

| Component | Meaning |
|---|---|
| `docker compose ps` | List the containers managed by the `docker-compose.yml` in this directory, plus their status |

I expect to see three services: `prometheus`, `grafana`, `app`. All should say `Up` or `running`.

If they're not running, bring them up:

```bash
docker compose up -d
```

| Component | Meaning |
|---|---|
| `docker compose up` | Start the services defined in `docker-compose.yml` |
| `-d` | Detached — run in the background, return the prompt |

Quick health checks on each:

```bash
curl -s http://localhost:3000/api/health
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:8080/metrics | head -20
```

| Component | Meaning |
|---|---|
| `curl -s` | Make an HTTP request, suppress the progress bar (`-s` = silent) |
| `http://localhost:3000/api/health` | Grafana's built-in health endpoint — returns JSON with `database: ok` if alive |
| `http://localhost:9090/-/healthy` | Prometheus health endpoint — returns "Prometheus Server is Healthy" |
| `http://localhost:8080/metrics` | The application's Prometheus metrics endpoint — what Prometheus scrapes from |
| `head -20` | Limit output to first 20 lines so we don't drown in metrics |

**What I'm looking for:** are all three answering? If yes, the infrastructure isn't the problem — the issue is in configuration or queries. If one is dead, that's where I start.

Assuming everything is up: the stack is alive but the dashboard is empty. That means it's a *behaviour* problem, not an *availability* problem. Different debugging mode now.

---

## Phase 2 — First look at Grafana

Open the dashboard:

```
http://localhost:3000
```

(Anonymous viewing is enabled by Compose env, so the dashboard is browsable without logging in. For admin actions later we'll log in: user `admin`, password `admin`.)

Navigate to **Dashboards → Application Dashboard**. Confirm the symptom: every panel says "No data".

**Now I think.** "No data" can mean a number of different things, and they need different fixes:

| Possibility | What it would mean |
|---|---|
| (a) The metrics don't exist anywhere | The app isn't producing them, or Prometheus isn't scraping them |
| (b) The metrics exist in Prometheus, but Grafana can't reach Prometheus | Data source problem |
| (c) Prometheus and Grafana are talking, but the dashboard's queries are wrong | Query problem |
| (d) Some queries are wrong, some are right | Mix of (b) and (c), or partial (c) |

Without more information, I can't tell which I'm in. I need to **eliminate possibilities one at a time**, starting with the cheapest check.

The cheapest check is (a): **do the metrics even exist?** Because if they don't, nothing else matters.

---

## Phase 3 — Eliminate "the metrics don't exist"

The point of this phase: **stop trusting Grafana for a minute and go straight to Prometheus.** If I can see metrics in Prometheus's own UI, I've eliminated possibility (a) entirely, and the problem is somewhere between Prometheus and Grafana — not upstream of either.

Open Prometheus directly:

```
http://localhost:9090
```

**Step 3a — Check the scrape targets.** Click **Status → Targets** in the top nav.

What I'm asking: "Is Prometheus actually pulling metrics from the app?"

I expect to see a `prometheus` job (Prometheus scraping itself) and an `app` job pointing at `app:8080`. Both should show **State: UP**.

If `app` shows DOWN, that's the smoking gun and I'd start there. Assume it's UP.

**Step 3b — Confirm the metric names exist.** Go to the **Graph** tab (the default landing page). In the expression bar, start typing the metrics the dashboard says it cares about. Or, faster, hit this URL to list every metric Prometheus has seen:

```bash
curl -s http://localhost:9090/api/v1/label/__name__/values | head -50
```

| Component | Meaning |
|---|---|
| `/api/v1/label/__name__/values` | Prometheus API endpoint that returns every distinct value of the special label `__name__` — i.e. every metric name Prometheus knows about |

In the output I should see things like `http_requests_total`, `http_request_duration_seconds_bucket`, `active_connections`. If they're all there, **possibility (a) is eliminated.** Metrics exist. The bug is elsewhere.

**This is a load-bearing diagnostic move.** Going to Prometheus first proves the data exists independently of Grafana. Now any "No data" in Grafana is Grafana's fault — either how it's connected, or how it's querying.

---

## Phase 4 — Test the data source

Now I move to Grafana and use *its* tooling to ask "are you connected to Prometheus?"

Log in to Grafana (`admin` / `admin`). Navigate:

**Connections → Data sources → Prometheus** *(in older Grafana the path is Configuration → Data sources)*

Scroll to the bottom and click **Save & test**.

**What I expect to see if it works:** a green banner saying "Data source is working".

**What I actually see:** a red banner. Something like *"HTTP Error Bad Gateway"* or *"dial tcp 127.0.0.1:9090: connect: connection refused"* or a timeout.

**This is Bug 1.** Now I think through it.

### Diagnostic pathway for Bug 1

1. The data source is configured in `provisioning/datasources/prometheus.yml`. Open it:

   ```bash
   cat provisioning/datasources/prometheus.yml
   ```

2. I see `url: http://localhost:9090`. **Why is that wrong?**

3. I'm running this from my host machine, where `localhost:9090` *does* reach Prometheus (because of the port mapping in `docker-compose.yml`). So the URL "looks right" if I'm thinking from my laptop's perspective.

4. **But this URL isn't used by my laptop.** It's used by the *Grafana container* when it tries to reach Prometheus. So the question becomes: what does `localhost` mean inside the Grafana container?

5. Inside any Docker container, `localhost` (`127.0.0.1`) means **that container itself**. Grafana's container has nothing listening on port 9090 — Grafana listens on 3000. So `http://localhost:9090` from inside Grafana resolves to "this container, port 9090" — which is empty. That's why the connection fails.

6. **How do containers actually reach each other in Docker Compose?** Compose creates an internal network and registers each service by its service name as a DNS hostname. From any container in the project, `prometheus` resolves to the Prometheus container's IP. So the right URL is `http://prometheus:9090`.

7. **Where do I find the service name?** It's the top-level key in `docker-compose.yml`. Quick check:

   ```bash
   grep -A1 "^services:" docker-compose.yml | head -20
   ```

   I see `prometheus:`, `grafana:`, `app:`. So `prometheus` is the right hostname.

### Apply Fix 1

Edit `provisioning/datasources/prometheus.yml`:

```yaml
# Before
url: http://localhost:9090

# After
url: http://prometheus:9090
```

Provisioning files are read by Grafana on startup, so changes don't take effect until Grafana is restarted:

```bash
docker compose restart grafana
sleep 5
```

| Component | Meaning |
|---|---|
| `docker compose restart grafana` | Stop and start just the `grafana` service. Container is recreated with the latest mounted files re-read. |
| `sleep 5` | Give Grafana a few seconds to come back up before we test it again |

Now go back to **Connections → Data sources → Prometheus → Save & test**. Green banner. Bug 1 done.

---

## Phase 5 — Bug 1 is fixed but the panels still say "No data"

Reload the dashboard. Most panels are still empty. *That's expected* — fixing the data source doesn't fix bad queries. It just means now we *can* tell whether the queries are the problem.

**The new question:** for each panel, what's wrong with its query?

**The technique:** open each panel's query in Prometheus's expression browser (`http://localhost:9090/graph`). Prometheus will tell me directly whether a query parses, runs, and returns data. Grafana's "No data" is uninformative; Prometheus's responses are *very* informative.

Let me also check what each panel is actually saying. Click any panel → "View" or hover over the panel title for an info icon. Some panels will show an actual error message ("parse error...", "unknown function..."). Others just say "No data" with no error — which is its own diagnostic clue (a query that *runs* but returns nothing is a different kind of bug from a query that *fails to parse*).

Let me look at the dashboard source to see what queries are in use:

```bash
cat provisioning/dashboards/app-dashboard.json
```

I can see four panels with four `expr` fields. I'll work through them one at a time.

---

## Phase 6 — Diagnose each query

### Panel 1: Request Rate — `rates(http_requests_total[5m])`

Paste this into Prometheus's expression browser:

```
rates(http_requests_total[5m])
```

Prometheus responds with a parse error:

> *"unknown function with name 'rates'"*

**Diagnostic pathway:**

1. Prometheus is telling me directly: there is no function called `rates`. So either it's a typo, or it's a function from a different system.
2. Do I know the right one? PromQL's standard function for "rate of change of a counter over time" is `rate()` — singular. Counters tick up; `rate()` smooths them into a per-second figure over a window.
3. Try `rate(http_requests_total[5m])` in the expression browser. It returns numbers. Confirmed.

### Apply Fix 2

In `provisioning/dashboards/app-dashboard.json`, change `rates(` to `rate(` in panel 1.

```json
"expr": "rate(http_requests_total[5m])"
```

### Panel 2: Error Rate — `... http_requests_total{status='500'} ...`

Paste it into Prometheus:

```
sum(rate(http_requests_total{status='500'}[5m])) / sum(rate(http_requests_total[5m])) * 100
```

Prometheus error:

> *"parse error: unterminated quoted string"* or similar — the parser blows up on the single quote.

**Diagnostic pathway:**

1. PromQL's grammar requires **double quotes** for label values. Single quotes are not valid PromQL. (This catches a lot of people who are coming from JavaScript or shell, where the quotes are interchangeable.)
2. Test with double quotes: `http_requests_total{status="500"}` — runs.
3. The expression in the JSON file uses single quotes. Need to change to double — but the JSON file itself uses double quotes for its string boundaries, so we have to escape the inner ones with backslashes.

### Apply Fix 3

```json
// Before
"expr": "sum(rate(http_requests_total{status='500'}[5m])) / sum(rate(http_requests_total[5m])) * 100"

// After
"expr": "sum(rate(http_requests_total{status=\"500\"}[5m])) / sum(rate(http_requests_total[5m])) * 100"
```

| Component | Meaning |
|---|---|
| `\"500\"` | Inside a JSON string, double quotes must be escaped with `\` so the JSON parser doesn't think the string is ending |

### Panel 3: P95 Duration — `histogram_quantile(95, ...)`

Paste it into Prometheus:

```
histogram_quantile(95, rate(http_request_duration_seconds_bucket[5m]))
```

Prometheus does NOT throw an error. It returns a value. The value is `+Inf` or some giant number.

**This is the most dangerous class of bug** — a query that *runs* but is meaningless. There's no error to alert me; I have to recognise that the result is wrong.

**Diagnostic pathway:**

1. The query parses and returns. So the syntax is fine. But the result is `+Inf` — not a sensible duration.
2. What could make `histogram_quantile` return infinity? Looking at the function: `histogram_quantile(φ, ...)` returns the φ-quantile from a histogram. φ stands for the quantile *as a fraction between 0 and 1*.
3. I'm passing `95`. The function is being asked for the "9500th percentile" — which doesn't exist. The function extrapolates beyond the maximum bucket and returns infinity.
4. To get the **95th percentile** I need `0.95`.
5. Sanity check: try `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` — returns a small floating-point number, plausibly a duration in seconds. Correct.

**The lesson here:** "the query runs" is not the same as "the query is correct". Always sanity-check the *value*, not just whether it errored.

### Apply Fix 4

```json
"expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
```

### Panel 4: Active Connections — `active_connection`

Paste it into Prometheus:

```
active_connection
```

No error. Empty result.

**Diagnostic pathway:**

1. No parse error means the query is valid PromQL. Empty result means no series in Prometheus has that name.
2. Empty results don't error — Prometheus treats "metric doesn't exist" as a valid empty result. This makes typos *very* easy to miss.
3. I already listed all metrics earlier (`/api/v1/label/__name__/values`). Let me grep for similar names:

   ```bash
   curl -s http://localhost:9090/api/v1/label/__name__/values | grep -i connection
   ```

4. Output shows `active_connections` (plural). Off by one letter.
5. Confirm in `app.py`:

   ```bash
   grep -i connection app.py
   ```

   Output: `ACTIVE_CONNECTIONS = Gauge('active_connections', 'Active connections')`

   The app exposes the metric as plural. The query uses singular. That's the bug.

### Apply Fix 5

```json
"expr": "active_connections"
```

---

## Phase 7 — Reload and verify

Restart Grafana so it picks up the dashboard JSON changes:

```bash
docker compose restart grafana
sleep 10
```

Reload the dashboard in the browser. All four panels should now render data:

- **Request Rate** — small per-second values, multiple lines for different `(method, status)` pairs
- **Error Rate (%)** — a single number, the proportion of 500s among all requests
- **Request Duration (p95)** — a small floating-point value (the simulated app generates 0.01–2.0 second durations, so p95 should land around 1.8–1.95)
- **Active Connections** — a gauge somewhere between 5 and 50

Run the validator:

```bash
lab validate monitoring/lab-056-grafana-dashboard-broken
```

All checks should pass.

---

## Phase 8 — Cleanup / reset

Containers are disposable, so no reset is needed in the strict sense. To return to the broken state for a re-run:

```bash
git checkout -- provisioning/datasources/prometheus.yml
git checkout -- provisioning/dashboards/app-dashboard.json
docker compose restart grafana
```

| Component | Meaning |
|---|---|
| `git checkout -- <file>` | Restore a file to its committed state, discarding local changes. The `--` separates the file path from any branch/ref names so git can't misinterpret it. |

To tear down completely:

```bash
docker compose down
```

| Component | Meaning |
|---|---|
| `docker compose down` | Stop and remove the containers, networks, and default volumes for this Compose project |

---

## Docker Lab vs Real Life

- **Dashboard-as-code:** Production teams version-control dashboards in Git and provision them via Terraform's Grafana provider, the Grafana HTTP API, or Grafonnet. Hand-editing JSON is error-prone — this lab is a microcosm of why.
- **Dashboard variables (templating):** Real dashboards use template variables (dropdowns) for environment, service, instance — one dashboard works across all environments instead of duplicating dashboards per env.
- **Annotations:** Production dashboards overlay deployment markers, incident timestamps, and config changes onto the graphs, correlating metric movements with events.
- **Alert rules in Grafana:** Modern Grafana (8+) defines alerts alongside panels, evaluated against the same data sources. Many shops still prefer Prometheus's own Alertmanager for richer routing.
- **Datasource URL is environment-dependent:** In Kubernetes, the URL would be `http://prometheus.monitoring.svc.cluster.local:9090` (a Kubernetes service DNS name). In Docker Compose it's the service name. In a managed Grafana Cloud setup it's an external URL with auth. Same concept; different DNS context.

---

## Key Concepts Learned

- **`localhost` inside a container means the container itself.** Always use the Docker Compose service name (or Kubernetes Service DNS name) when one container needs to reach another. This is the single most common mistake when wiring together a Compose stack.
- **PromQL `rate()` (singular)** computes per-second rates of counters over a window. There is no `rates()`.
- **PromQL label matchers use double quotes only**, e.g. `{status="500"}`. Single quotes are a syntax error.
- **`histogram_quantile(φ, ...)` takes φ as a decimal between 0 and 1**, not a percentage. `0.95` for p95, `0.99` for p99. Passing `95` returns infinity silently.
- **Prometheus does not error on non-existent metric names.** A typo silently returns empty. Always confirm metric names against `/api/v1/label/__name__/values` or your application's source code.
- **"Runs without error" ≠ "correct".** Always sanity-check the actual value a query returns.

---

## Common Mistakes & Gotchas

- **Treating "No data" as one symptom.** It can mean broken connectivity, broken queries, or missing metrics — these need different diagnostic moves. Always test each layer in isolation before guessing.
- **Editing provisioned dashboards in the Grafana UI.** Changes are lost on the next provisioning run (i.e. on Grafana restart). For provisioned dashboards, edit the source JSON and re-provision.
- **Forgetting that JSON-encoded PromQL needs escaped double quotes** (`\"`). The JSON file's outer quotes are double; PromQL's inner quotes are also double; the inner ones must be escaped.
- **Not restarting Grafana after editing provisioning files.** Provisioning is read on container start, not on file change. A restart is required for changes to take effect.
- **Trusting the ticket's diagnosis.** The ticket said "Prometheus is collecting metrics fine" — and that turned out to be true. But on a different ticket the assumption could be wrong. Always re-confirm the upstream layers before working on downstream ones.
