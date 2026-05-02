# Solution Walkthrough — Lab 053: Alert Fatigue Triage

## TLDR (Plain English)

**The problem in one sentence:** Whoever set up the monitoring system configured every alert to fire on completely normal conditions and tagged all of them as "critical," so the on-call engineer's phone never stops ringing — and now the team ignores every alert, including the real ones.

**What's actually wrong:**
- Thresholds are set at the floor instead of the ceiling. CPU alerts at 1% (any running computer is above 1%). Response-time alerts at 10ms (faster than physically possible for most apps). SSL alerts when the certificate expires within a year (that's basically every cert).
- Every single alert is labelled "critical," which means every alert pages someone. There's no distinction between "the website is down" and "CPU briefly hit 3%."
- Alerts fire on individual events instead of patterns. One log line containing the word ERROR pages someone. One container restarting (which happens normally on deploys) pages someone.

**How we fix it:**
1. Read the current config and the alert log to confirm the diagnosis.
2. Apply four triage principles to every alert: is it actionable, is the threshold realistic, is the severity proportionate, should it fire on rates instead of single events.
3. Rewrite the config with sensible thresholds, a proper severity ladder (warning vs critical), and the noisiest event-based alerts either deleted or rate-based.
4. Save it as a separate `alerts-fixed.json` so the broken file is preserved for review.

You're not deploying anything new. You're rewriting one config file to stop drowning the on-call rota in noise.

---

## The Ticket

```
INCIDENT-MON-004: On-call burnout
Reporter: Engineering Manager
Priority: P2

200+ alerts/day. 95% non-actionable. Team is ignoring alerts. Real
incidents are being missed in the noise. Triage and fix.
```

That's it. No file paths, no hints about what the config looks like, no clue what tooling is in play. You're an SRE arriving at a problem that's been festering — figure out where the alert config lives, work out what's wrong with it, and rebuild it sensibly.

---

## The Cold-Ticket Walkthrough

### Step 0 — What does the ticket actually tell us?

Before touching anything, read the ticket twice. What facts do we have?

- **200+ alerts/day** — this is volume. We can verify this by counting log entries.
- **95% non-actionable** — this is the diagnosis the reporter has already made. We should confirm it independently rather than trust it.
- **Team is ignoring alerts** — this is the consequence (alert fatigue), not the cause.
- **Real incidents being missed** — this is the business impact, which is why this is a P2.

So the cause is somewhere in the alert configuration: either too many alerts, alerts firing on wrong conditions, or both. We need to find the alert config.

### Step 1 — Find the alert configuration

We don't yet know where the config lives. In a real environment this might live in Prometheus rules, Datadog monitors, an Alertmanager config, or — as in this lab — a JSON file on disk. Start with the obvious filesystem locations.

```bash
ls /opt/
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `ls` | List directory contents |
| `/opt/` | Standard Linux location for "optional" or third-party software. Monitoring tools commonly install here. |

We see a `monitoring` directory. That's promising.

```bash
ls /opt/monitoring/
```

Two files: `alerts.json` and `alert-log.txt`. The first is almost certainly the configuration; the second is the evidence of what's been firing. Read both.

> **How would I know to look in `/opt`?** Standard FHS (Filesystem Hierarchy Standard) convention. Vendor-supplied or self-hosted monitoring tools typically install under `/opt/<toolname>/`. If `/opt` was empty, the next places to check would be `/etc/` (config files), `/var/lib/` (state files), or `find / -name "*alert*" 2>/dev/null` to brute-force search.

> ### ⚠️ Stop — first-instinct check before touching anything
>
> Your reflex when you find a broken config is going to be **"I'll just edit this file and fix it."** Resist that. The lab brief, and good engineering practice, says you write the fix to a **new file alongside the original**:
>
> - Original `alerts.json` stays untouched — preserves the broken state for postmortem, review, comparison
> - New file `alerts-fixed.json` contains your corrected config
> - Reviewer or future-you can diff the two files to see exactly what changed and why
> - Rollback is one command: `mv alerts-fixed.json alerts.json`
>
> This generalises far beyond this lab. It's the same instinct that says **never edit production config in place**, **always open a PR rather than committing to main**, and **keep your `terraform plan` output before you `apply`**. The diff is the audit trail. Lose the diff and you've lost half the value of the fix.
>
> If you've already edited the original by mistake, see the "Recovering from in-place edits" section near the end of this document.

### Step 2 — Read the current config

```bash
cat /opt/monitoring/alerts.json
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `cat` | Concatenate and print file contents to stdout |
| `/opt/monitoring/alerts.json` | The file we want to read |

Output:

```json
{
  "alerts": [
    {"name": "cpu_above_1_percent", "threshold": 1, "severity": "critical", "description": "CPU usage above 1%"},
    {"name": "memory_above_10_percent", "threshold": 10, "severity": "critical", "description": "Memory above 10%"},
    {"name": "disk_above_50_percent", "threshold": 50, "severity": "critical", "description": "Disk above 50%"},
    {"name": "http_5xx_any", "threshold": 1, "severity": "critical", "description": "Any 5xx error"},
    {"name": "response_time_above_10ms", "threshold": 10, "severity": "critical", "description": "Response time above 10ms"},
    {"name": "container_restart", "threshold": 1, "severity": "critical", "description": "Any container restart"},
    {"name": "ssl_cert_expiry_365d", "threshold": 365, "severity": "critical", "description": "SSL cert expires within 365 days"},
    {"name": "log_error_any", "threshold": 1, "severity": "critical", "description": "Any ERROR in logs"},
    {"name": "network_packet_loss_any", "threshold": 0.01, "severity": "critical", "description": "Any packet loss > 0.01%"},
    {"name": "pod_pending_1s", "threshold": 1, "severity": "critical", "description": "Pod pending for 1 second"}
  ]
}
```

Read this slowly. What do you actually see?

- 10 alerts in total
- Every single `severity` is `critical`
- The names and thresholds are pathological: CPU at 1%, memory at 10%, response time at 10ms, SSL at 365 days, packet loss at 0.01%

A normal Linux server idles somewhere between 1-5% CPU. A healthy web app responds in 50-300ms. Most TLS certificates are issued for 90 days. **These thresholds are set at the floor of normal operation — they will fire constantly.**

> **The "everything is critical" smell.** If every alert is critical, no alert is critical. The whole point of severity levels is to tell the on-call engineer "this is the one to wake up for." When the labelling carries no information, it becomes noise.

> ### Detour — "Wait, what's actually reading this JSON?"
>
> A good question to ask at this point. **In this lab, nothing is.** The container has no Prometheus, no Alertmanager, no agent. The JSON file is a deliberately stripped-down stand-in for what a production alert config looks like. You can verify this:
>
> ```bash
> ps aux           # no monitoring processes running
> ls /etc/prometheus 2>/dev/null   # no prometheus config
> ```
>
> So why simulate? Because the lesson here is the **triage skill** — reading a config, spotting bad thresholds, applying severity logic, deciding what to delete. That skill transfers identically whether the consumer is Prometheus, Datadog, or a homegrown shell script. Spinning up a real Prometheus + Alertmanager + node-exporter stack just to demonstrate "1% CPU is a stupid threshold" would be 90% setup, 10% lesson.
>
> **In real life, the alert config almost always lives in YAML, read by the monitoring tool itself.** The dominant pattern across the industry:
>
> | System | Where the config lives | Format |
> |---|---|---|
> | Prometheus + Alertmanager | `prometheus.yml` references `*.rules.yml` files; Alertmanager has a separate `alertmanager.yml` for routing | YAML, with PromQL expressions instead of plain thresholds |
> | Prometheus on Kubernetes | `PrometheusRule` custom resources managed by the Prometheus Operator | YAML Kubernetes manifests |
> | Datadog / New Relic | UI or Terraform `datadog_monitor` resources | Terraform / API |
> | AWS CloudWatch | `aws_cloudwatch_metric_alarm` Terraform resources or console | Terraform / console |
>
> A real Prometheus rule for "CPU above 80%" looks like this:
>
> ```yaml
> - alert: HighCPU
>   expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
>   for: 10m
>   labels:
>     severity: warning
>   annotations:
>     summary: "CPU above 80% on {{ $labels.instance }}"
>     runbook: "https://wiki.internal/runbooks/high-cpu"
> ```
>
> Three things in that real-world rule that the simulation doesn't show but matter enormously:
>
> 1. **`expr`** — the condition is a PromQL query, not a flat threshold. The query calculates "average CPU usage over 5 minutes," and the threshold (`> 80`) is just the tail end.
> 2. **`for: 10m`** — the condition must hold *continuously for 10 minutes* before the alert fires. This single field eliminates a huge amount of noise. CPU briefly spikes during a backup? Swallowed. CPU sits at 85% for half an hour? Fires. Our simulated config has no concept of duration.
> 3. **`labels` and `annotations`** — `severity: warning` is a *label* that drives routing in Alertmanager (criticals page, warnings ticket). Annotations carry runbook URLs so the on-call engineer at 3 AM has a starting point.
>
> The four-question triage you're about to do is identical regardless of tool. Once you've made the judgement calls, plugging the result into a real Prometheus rule file is just syntax.

### Step 3 — Confirm the diagnosis with the alert log

The config tells us *what would fire*. The log tells us *what is firing*. If the diagnosis is right, we should see those low thresholds being hit by completely normal values.

```bash
cat /opt/monitoring/alert-log.txt
```

Output:

```
2024-01-15 08:00:01 CRITICAL cpu_above_1_percent - CPU at 3% on web-01
2024-01-15 08:00:01 CRITICAL memory_above_10_percent - Memory at 45% on web-01
2024-01-15 08:00:01 CRITICAL response_time_above_10ms - Response 42ms on /api/users
2024-01-15 08:00:02 CRITICAL disk_above_50_percent - Disk at 62% on db-01
2024-01-15 08:00:03 CRITICAL http_5xx_any - 1 error on /api/payments (500)
2024-01-15 08:00:05 CRITICAL container_restart - web-worker-3 restarted (OOM)
2024-01-15 08:00:10 CRITICAL log_error_any - ERROR: Failed to send analytics event
2024-01-15 08:00:15 CRITICAL ssl_cert_expiry_365d - cert expires in 340 days
2024-01-15 08:01:01 CRITICAL cpu_above_1_percent - CPU at 5% on web-02
2024-01-15 08:01:01 CRITICAL memory_above_10_percent - Memory at 38% on web-02
... (repeats 200+ times per day)
```

Diagnosis confirmed. Look at the actual values being reported:

- **CPU at 3% / 5%** — this is an idle web server. Anyone with a Linux background knows this.
- **Memory at 45% / 38%** — perfectly healthy.
- **Response time of 42ms** — that's good performance, not a problem.
- **Disk at 62%** — fine.
- **One 500 error on `/api/payments`** — a single error in isolation could be anything: a bad client, a transient glitch, a retry. It's not an incident on its own.
- **Single `container_restart` (OOM)** — worth knowing, but a single restart isn't a P1. The container restarted; that's what containers do.
- **Single ERROR log line about analytics** — analytics is non-critical, and "ERROR" appearing once is not an outage.
- **SSL cert expires in 340 days** — this is fine for nine months and could literally have been raised yesterday.

The on-call engineer is being paged for a healthy system. No wonder they've stopped looking.

### Step 4 — Decide the triage principles before writing any config

Don't dive into rewriting yet. First, agree the principles you'll apply to every alert. This is what separates "I changed some numbers" from a defensible engineering decision.

For each alert, ask four questions:

**1. Is this actionable?** Would a sensible on-call engineer take any action when this fires? "CPU at 3%" — no. "CPU sustained at 95%" — yes, investigate. If an alert isn't actionable, delete it.

**2. Is the threshold realistic?** A threshold should sit *above* the normal operating range, not at its floor. If CPU normally runs 5-50%, set the warning at 80% and critical at 95%. If response time normally sits at 50-500ms, set the warning at 2 seconds. Industry rough guides:

| Metric | Warning | Critical |
|---|---|---|
| CPU | 80% sustained | 95% sustained |
| Memory | 85% | 95% |
| Disk | 85% | 95% |
| HTTP 5xx rate | 1-2% of requests | 5%+ of requests |
| P95 response time | 2x normal baseline | 5x normal baseline |
| SSL cert expiry | 30 days | 7 days |

**3. Is the severity proportionate?** The severity ladder should mean something:

| Severity | Meaning | Routing |
|---|---|---|
| `critical` | Wake someone up. The system is down or about to be. | Page on-call immediately |
| `warning` | Something needs human attention soon. | Ticket for business hours |
| `info` | For dashboards and audit only. | No notification |

If you can't justify "wake someone up at 3 AM," it isn't critical.

**4. Should this be a rate, not a single event?** A single 500 error means almost nothing — clients retry, networks blip, deployments cause brief errors. **5% of all requests returning 500** is an incident. The same logic applies to log errors, container restarts, and packet loss.

### Step 5 — Apply the principles, alert by alert

Walk through each of the 10 original alerts and decide its fate. This is the actual triage. Three possible verdicts: **keep & fix the threshold**, **keep & convert to a rate**, or **delete**.

| # | Original alert | Decision | Reasoning |
|---|---|---|---|
| 1 | `cpu_above_1_percent` (1%, critical) | **Keep, fix** | Real metric, broken threshold. Split into warning at 80%, critical at 95% — proper severity ladder. |
| 2 | `memory_above_10_percent` (10%, critical) | **Keep, fix** | Same pattern. Warning at 85%, critical at 95%. Modern Linux uses memory aggressively for caches, so 85% is normal-busy, not yet a problem. |
| 3 | `disk_above_50_percent` (50%, critical) | **Keep, fix** | Disk is special — when it fills, services hard-fail. Warning at 80%, critical at 95%. |
| 4 | `http_5xx_any` (1 error, critical) | **Keep, convert** | Single error is noise. Convert to *error-rate* alert at 5% of total requests, critical. The threshold value is now a percentage, not a count — name and description must reflect that. |
| 5 | `response_time_above_10ms` (10ms, critical) | **Keep, fix and demote** | Real metric, absurd threshold. Warning at 2000ms (P95). **Severity demoted to warning** — slow ≠ down. If you want a critical tier, add a second alert at 5000ms. |
| 6 | `container_restart` (1, critical) | **Delete** | Single restarts are normal (rolling deploys, OOM kills, health-check tweaks). A *trend* alert (">10 restarts in 5 minutes") would be valid; a single-event alert is not. |
| 7 | `ssl_cert_expiry_365d` (365 days, critical) | **Keep, fix** | Real concern, broken threshold. Warning at 30 days remaining. Rename to `ssl_cert_expiry_30d` so name, threshold, and description all tell the same story. |
| 8 | `log_error_any` (1, critical) | **Delete** | "ERROR" appearing in a log line is meaningless without context. Belongs in a log-aggregation tool (Loki, Splunk, ELK) with rate-based queries, not a paging system. |
| 9 | `network_packet_loss_any` (0.01%, critical) | **Delete** | The internet has packet loss. 0.01% is below the noise floor of any real network. |
| 10 | `pod_pending_1s` (1s, critical) | **Delete** | Pods pend for several seconds during normal scheduling. A meaningful alert would be "pod pending for >5 minutes" — and that belongs in cluster monitoring (`kube_pod_status_phase`), not in the general alert set. |

**Result: 9 alerts down from 10** (we added a memory critical tier alongside the CPU and disk ladders), with clear warning/critical severity tiers and realistic thresholds.

> **Why not just raise the thresholds and keep all 10?** Because some of those alerts shouldn't exist at all in this form. Alerting on a single log line containing "ERROR" is fundamentally a category error — that data belongs in a log search interface, not a paging system. Delete is sometimes the right answer.

### Step 6 — Write the new config

We don't overwrite `alerts.json`. We create `alerts-fixed.json` alongside it, so the broken state is preserved for review and rollback (see the callout earlier on first-instinct file editing).

```bash
cat > /opt/monitoring/alerts-fixed.json << 'EOF'
{
  "alerts": [
    {"name": "cpu_above_80_percent", "threshold": 80, "severity": "warning", "description": "CPU usage above 80%"},
    {"name": "cpu_above_95_percent", "threshold": 95, "severity": "critical", "description": "CPU usage above 95%"},
    {"name": "memory_above_85_percent", "threshold": 85, "severity": "warning", "description": "Memory above 85%"},
    {"name": "memory_above_95_percent", "threshold": 95, "severity": "critical", "description": "Memory above 95%"},
    {"name": "disk_above_80_percent", "threshold": 80, "severity": "warning", "description": "Disk above 80%"},
    {"name": "disk_above_95_percent", "threshold": 95, "severity": "critical", "description": "Disk above 95%"},
    {"name": "http_5xx_rate", "threshold": 5, "severity": "critical", "description": "5xx error rate above 5% of total requests"},
    {"name": "response_time_above_2000ms", "threshold": 2000, "severity": "warning", "description": "P95 response time above 2000ms"},
    {"name": "ssl_cert_expiry_30d", "threshold": 30, "severity": "warning", "description": "SSL cert expires within 30 days"}
  ]
}
EOF
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `cat > <file>` | Take stdin and write it to `<file>` (overwriting if it exists) |
| `<< 'EOF'` | Heredoc — read stdin until a line containing exactly `EOF`. The single quotes around `'EOF'` prevent shell variable expansion inside the content. Useful when the content contains `$` or backticks you want preserved literally. |
| `EOF` (closing) | Marker that ends the heredoc input |

> **Why heredoc instead of `vi` or `nano`?** It's reproducible. You can paste the same command into a runbook, a script, or an Ansible playbook and get exactly the same file every time. Editor sessions don't survive being copied into a postmortem.

> ### Common JSON gotchas when hand-editing
>
> JSON is unforgiving. Three mistakes you will absolutely make at some point:
>
> **1. Trailing commas.** JSON does **not** allow a comma after the last element of an array or object. JavaScript does (since ES2017). Python dicts do. YAML does. JSON does not.
>
> ```json
> // BROKEN — trailing comma after the last alert
> {
>   "alerts": [
>     {"name": "cpu_high", "threshold": 80, "severity": "warning"},
>     {"name": "ssl_cert_expiry_30d", "threshold": 30, "severity": "warning"},   ← this comma is fatal
>   ]
> }
> ```
>
> Always check the last element of every array and the last key-value of every object. The error message you get from a JSON parser is usually helpful — `json.decoder.JSONDecodeError: Expecting property name enclosed in double quotes: line N column M`.
>
> **2. Single quotes instead of double quotes.** JSON requires double quotes around strings *and* keys. `'name'` is invalid. So is `name` (unquoted). Only `"name"` works.
>
> **3. Comments.** JSON has no comment syntax. `//` and `/* ... */` are both invalid. If you want comments, either use a description field as data (as we do here) or move to YAML.
>
> **The mandatory verification step:** before running the lab validator, always verify the JSON parses cleanly:
>
> ```bash
> python3 -m json.tool /opt/monitoring/alerts-fixed.json
> ```
>
> If it's valid, you'll see the pretty-printed file. If it's not, you'll get a parse error with a line and column number. Treat this as a non-negotiable step — it costs you a second and saves you a confusing validator failure.



**Command breakdown:**

| Component | What it does |
|---|---|
| `cat > <file>` | Take stdin and write it to `<file>` (overwriting if it exists) |
| `<< 'EOF'` | Heredoc — read stdin until a line containing exactly `EOF`. The single quotes around `'EOF'` prevent shell variable expansion inside the content. Useful when the content contains `$` or backticks you want preserved literally. |
| `EOF` (closing) | Marker that ends the heredoc input |

> **Why heredoc instead of `vi` or `nano`?** It's reproducible. You can paste the same command into a runbook, a script, or an Ansible playbook and get exactly the same file every time. Editor sessions don't survive being copied into a postmortem.

### Step 7 — Sanity-check the new config

Before declaring victory, prove to yourself the file is what you think it is. (This is the same `python3 -m json.tool` step we flagged as mandatory in the JSON gotchas callout — repeating here because if you skip it, the lab validator will fail with a confusing cascade of errors and you'll waste time debugging the wrong layer.)

```bash
python3 -m json.tool /opt/monitoring/alerts-fixed.json
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `python3 -m json.tool` | Run Python's built-in JSON pretty-printer. If the JSON is malformed, this errors loudly. |
| `<file>` | The file to validate and pretty-print |

If the file is valid, you'll see the formatted JSON. If it's not, you'll get a parse error pointing at the line.

Now check the new alerts at a glance:

```bash
python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
for a in data['alerts']:
    print(f\"{a['severity']:10s}  {a['name']:30s}  threshold={a['threshold']}\")
print(f'\\nTotal: {len(data[\"alerts\"])} alerts')
print(f'Severities: {sorted(set(a[\"severity\"] for a in data[\"alerts\"]))}')"
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `python3 -c "<code>"` | Run a one-liner Python script |
| `json.load(f)` | Parse the JSON file into a Python dict |
| The f-string formatting | Pads each column so the output lines up neatly |

Expected output:

```
warning     cpu_above_80_percent            threshold=80
critical    cpu_above_95_percent            threshold=95
warning     memory_above_85_percent         threshold=85
critical    memory_above_95_percent         threshold=95
warning     disk_above_80_percent           threshold=80
critical    disk_above_95_percent           threshold=95
critical    http_5xx_rate                   threshold=5
warning     response_time_above_2000ms      threshold=2000
warning     ssl_cert_expiry_30d             threshold=30

Total: 9 alerts
Severities: ['critical', 'warning']
```

9 alerts, two severity levels, no thresholds at the floor, no count-based event alerts surviving. That's a defensible config.

### Step 8 — Run the validator

Exit the container first — `lab validate` runs from the Pi host, not from inside the container:

```bash
exit
lab validate 053
```

The validator checks:
- The fixed file exists and is valid JSON
- The alerts array is non-empty
- The total alert count is between 4 and 9
- Every alert has the required fields (`name`, `threshold`, `severity`)
- CPU and memory thresholds are at least 70%
- Multiple severity levels are used, including `warning` specifically
- No more than 60% of alerts are `critical` (catches "everything is critical" anti-patterns even after a partial fix)
- Single-event "noisy" alerts (log_error, pod_pending, packet_loss, container_restart) — if kept at all — have thresholds raised above 1

If any check fails, the validator exits non-zero and prints which check failed. **All ten ❌ on the first attempt is the signature of a missing file** — usually because you edited `alerts.json` instead of creating `alerts-fixed.json`. See the recovery section below.

---

## Recovering from in-place edits

If you've edited `alerts.json` directly instead of creating `alerts-fixed.json`, the validator will fail every check (because it looks for `alerts-fixed.json` and finds nothing). Here's how to recover.

### The clean recovery — re-run the setup script

The container's setup script (`/opt/inject-faults.sh`) is idempotent — it uses `cat > file << EOF`, which **overwrites** the file every time. Re-running the script restores the original broken state in seconds:

```bash
docker exec -it lab053-alert-fatigue-triage bash
/opt/inject-faults.sh
cat /opt/monitoring/alerts.json   # confirm the broken config is back
```

You should see the original 10 alerts with the absurd thresholds. Now write your fix to the **correct** path (`alerts-fixed.json`, not `alerts.json`).

> **Why the script is safe to re-run:** the heredoc-with-`>` pattern always overwrites. There's no append, no prompt, no "are you sure" — it just writes. Many setup scripts in lab environments are written this way deliberately, exactly so they can serve as resets.

### The nuclear option — recreate the container

If for any reason the setup script doesn't restore cleanly (you've modified the script, the container has been in some weird state for a while, you can't be sure of what's been changed), the universal "I've broken everything beyond recognition" lever is to destroy and recreate the container:

```bash
cd ~/cloud-engineer-labs/cloud-labs/monitoring-labs/lab-053-alert-fatigue-triage
docker compose down
docker compose up -d
docker exec -it lab053-alert-fatigue-triage bash
```

This wipes the container entirely and rebuilds it from the image, which runs `inject-faults.sh` automatically as part of the container's `CMD`. You're guaranteed a fresh broken state.

### Why not just edit `alerts.json` and rename it?

Tempting, but the validator specifically checks for both files coexisting (or at least, for `alerts-fixed.json` to exist as a standalone file). And in real life, the principle is to preserve the broken state for the postmortem. **The diff between broken and fixed is the audit trail. Lose the diff and you've lost half the value of the fix.**


---

## Lab vs Real Life

This lab uses a static JSON file as a stand-in for "the alert configuration." In production, the config lives in one of:

- **Prometheus alerting rules** (YAML files referenced from `prometheus.yml`, evaluated against scraped metrics, fired through Alertmanager)
- **Alertmanager config** (routes alerts to PagerDuty, Slack, email by severity, team, or labels — handles grouping and silencing)
- **Datadog monitors / New Relic alerts / Grafana alerts** (UI-driven SaaS equivalents)
- **Kubernetes `PrometheusRule` CRDs** (the same Prometheus rules but managed as Kubernetes resources via the Prometheus Operator)

The principles are identical regardless of tooling: actionable, realistic threshold, proportionate severity, rate not event. Only the syntax changes.

A few things real production setups do that this lab simplifies:

- **Alert grouping** — when CPU is high *and* memory is high *and* response time is bad, you almost certainly want one combined alert (the root cause), not three separate pages. Alertmanager groups by labels.
- **Silencing during maintenance** — when you're deploying, alerts that fire because of the deploy itself need to be suppressed. Alertmanager has `silences`.
- **Runbook links** — every alert in production should link to a runbook explaining what to check and how to fix it. The on-call engineer at 3 AM does not want to think.
- **SLO burn-rate alerts** — instead of "CPU is high," modern teams alert on "we are burning through our error budget 10x faster than the SLO allows." This is more actionable because it ties directly to the user-visible SLA.
- **Routing by severity** — `critical` goes to PagerDuty (phone call). `warning` goes to a ticket queue or Slack channel. `info` is dashboard-only. The severity ladder is operationally meaningful.

---

## Pi / K3s Environment Notes

This lab runs entirely inside a single Docker container — no Kubernetes, no Pi-specific gotchas. The container starts on `docker compose up -d`, the broken alert config is written by the container's startup command, and the entire exercise is filesystem-level inside that container. It will run identically on x86 or ARM64.

The only Pi-relevant note: the container image is built `FROM ubuntu:22.04`, which has multi-arch images on Docker Hub, so it pulls cleanly on the Pi without any platform overrides.

---

## Key Concepts Learned

- **Thresholds belong above the normal range, not at its floor.** If you alert at the floor, you're alerting on "the system is on."
- **Severity is a contract with the on-call engineer.** Critical means "page me." Warning means "ticket me." If everything is critical, you've broken the contract and the on-call rota has stopped trusting it.
- **Alert on rates, not single events.** One 500 error is noise. 5% of requests returning 500 is an incident. The same applies to log errors, restarts, packet loss — anything where one occurrence is uninteresting but a sustained pattern is meaningful.
- **Deletion is a valid fix.** Some alerts shouldn't exist in this form at all. A "log line contains ERROR" alert belongs in a log search tool, not a paging system. Don't be afraid to delete.
- **Alert fatigue is a safety issue.** When 95% of pages are noise, the team learns to ignore pages. The 5% that are real then go unanswered. Tuning alerts is not housekeeping — it's incident-response infrastructure.
- **Preserve the broken state when fixing in lab/staging.** Writing to `alerts-fixed.json` instead of overwriting `alerts.json` lets you compare, review, and roll back. In production this maps to the equivalent: a PR diff, a config-management revision, a Prometheus rule change with a Git history.

---

## Common Mistakes

- **Editing `alerts.json` in place instead of creating `alerts-fixed.json`.** This is the most common first-attempt failure on this lab. Your reflex when you see a broken config is to fix it in place. Don't. Create a new file alongside, preserve the broken state, leave the diff for review. See the "Recovering from in-place edits" section above if you've already done it.
- **Trailing commas in JSON.** JSON does not allow a comma after the last element of an array or object. JavaScript and Python do; YAML does. Always check the last element, and always run `python3 -m json.tool <file>` before declaring victory.
- **Mismatched name, threshold, and description.** If the alert is called `ssl_cert_expiry_365d`, the threshold is `30`, and the description says "expires within 30 days," all three disagree and you've made the file harder to maintain than it needs to be. Rename and renumber so they tell the same story.
- **Inconsistent severity ladders across metrics.** If CPU has both warning (80%) and critical (95%) tiers, but memory only has critical (85%), that's a smell — either memory needs a warning tier, or you've made memory artificially more urgent than CPU. Be consistent.
- **Count-based alerts dressed up as rates.** Renaming `http_5xx_any` to `http_5xx_rate` doesn't make it a rate alert if the threshold is still a raw count. The *meaning* of the threshold value has to change too — "5" needs to be "5 percent of total requests," not "5 errors total."
- **Treating slow as urgent as down.** Response time and error rate are different categories. A slow response is degraded experience (warning); a non-response or 5xx burst is an outage (critical). Don't lump them together.
- **Raising thresholds without removing dead alerts.** If `log_error_any` shouldn't exist at all, raising its threshold from 1 to 10 doesn't fix it — you still have an unactionable alert, just one that fires less often. Sometimes the right answer is delete.
- **Keeping everything as critical.** It feels safer ("I don't want to miss anything") but it's the opposite — it guarantees real critical alerts get ignored alongside the noise.
- **Setting one global threshold for everything.** CPU and disk and response time and SSL all need different thresholds based on what's normal for that metric. Don't blanket everything at 80%.
- **Confusing alert deletion with metric deletion.** You can delete the *alert* on packet loss without deleting the *metric* — keep collecting the data, just stop paging on it. The metric still appears on dashboards for diagnostic use.
- **No runbooks.** This lab doesn't enforce it, but in production every critical alert should link to a runbook. Otherwise the on-call engineer is reverse-engineering the system at 3 AM.
- **Not reviewing alerts on a cadence.** Alerts decay — what was true six months ago may be wrong now. A monthly review of "which alerts fired, which were actionable, which were noise" keeps the configuration honest.
