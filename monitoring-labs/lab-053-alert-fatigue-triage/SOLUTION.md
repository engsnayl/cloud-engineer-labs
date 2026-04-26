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

Walk through each of the 10 original alerts and decide its fate. This is the actual triage.

| # | Original alert | Decision | Reasoning |
|---|---|---|---|
| 1 | `cpu_above_1_percent` (1%, critical) | **Keep, fix** | Real metric, broken threshold. Split into warning at 80%, critical at 95%. |
| 2 | `memory_above_10_percent` (10%, critical) | **Keep, fix** | Same as CPU. Single warning at 85%. |
| 3 | `disk_above_50_percent` (50%, critical) | **Keep, fix** | Disk is special — when it fills, things break hard. Warning at 85%, critical at 95%. |
| 4 | `http_5xx_any` (1 error, critical) | **Keep, convert** | Single error is noise. Convert to error-rate alert at 5%, critical. |
| 5 | `response_time_above_10ms` (10ms, critical) | **Keep, fix** | Real metric, absurd threshold. Warning at 2000ms (P95). |
| 6 | `container_restart` (1, critical) | **Delete** | Single restarts are normal (rolling deploys, OOM kills, health-check tweaks). Worth a *trend* alert (">10 restarts in 5 minutes") but not a single-event alert. Out of scope here. |
| 7 | `ssl_cert_expiry_365d` (365 days, critical) | **Keep, fix** | Real concern, broken threshold. Warning at 30 days; certs are usually renewed automatically. |
| 8 | `log_error_any` (1, critical) | **Delete** | "ERROR" appearing in logs is meaningless without context. Belongs in a log-aggregation tool with rate-based queries, not a paging alert. |
| 9 | `network_packet_loss_any` (0.01%, critical) | **Delete** | The internet has packet loss. 0.01% is below the noise floor of any real network. |
| 10 | `pod_pending_1s` (1s, critical) | **Delete** | Pods pend for several seconds during normal scheduling. A meaningful alert would be "pod pending for >5 minutes" — but this is a Kubernetes-specific concern that should live in cluster monitoring, not the general alert set. |

**Result: 8 alerts down from 10**, with clear severity tiers and realistic thresholds.

> **Why not just raise the thresholds and keep all 10?** Because some of those alerts shouldn't exist at all in this form. Alerting on a single log line containing "ERROR" is fundamentally a category error — that data belongs in a log search interface, not a paging system. Delete is sometimes the right answer.

### Step 6 — Write the new config

We don't overwrite `alerts.json`. We create `alerts-fixed.json` alongside it, so the broken state is preserved for review and rollback.

```bash
cat > /opt/monitoring/alerts-fixed.json << 'EOF'
{
  "alerts": [
    {
      "name": "cpu_high",
      "threshold": 80,
      "severity": "warning",
      "description": "CPU usage sustained above 80% — investigate"
    },
    {
      "name": "cpu_critical",
      "threshold": 95,
      "severity": "critical",
      "description": "CPU usage sustained above 95% — immediate action"
    },
    {
      "name": "memory_high",
      "threshold": 85,
      "severity": "warning",
      "description": "Memory usage above 85%"
    },
    {
      "name": "disk_high",
      "threshold": 85,
      "severity": "warning",
      "description": "Disk usage above 85% — plan cleanup"
    },
    {
      "name": "disk_critical",
      "threshold": 95,
      "severity": "critical",
      "description": "Disk usage above 95% — immediate action"
    },
    {
      "name": "http_5xx_rate",
      "threshold": 5,
      "severity": "critical",
      "description": "5xx error rate above 5% of total requests"
    },
    {
      "name": "response_time_p95_high",
      "threshold": 2000,
      "severity": "warning",
      "description": "P95 response time above 2000ms"
    },
    {
      "name": "ssl_cert_expiry",
      "threshold": 30,
      "severity": "warning",
      "description": "SSL certificate expires within 30 days"
    }
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

### Step 7 — Sanity-check the new config

Before declaring victory, prove to yourself the file is what you think it is.

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
warning     cpu_high                        threshold=80
critical    cpu_critical                    threshold=95
warning     memory_high                     threshold=85
warning     disk_high                       threshold=85
critical    disk_critical                   threshold=95
critical    http_5xx_rate                   threshold=5
warning     response_time_p95_high          threshold=2000
warning     ssl_cert_expiry                 threshold=30

Total: 8 alerts
Severities: ['critical', 'warning']
```

8 alerts, two severity levels, no thresholds at the floor. That's a defensible config.

### Step 8 — Run the validator

```bash
lab validate monitoring/lab-053-alert-fatigue-triage
```

The validator checks:
- The fixed file exists and is valid JSON
- The alerts array is non-empty
- The total alert count is between 4 and 9
- Every alert has the required fields
- CPU and memory thresholds are at least 70%
- Multiple severity levels including `warning`
- No more than 60% of alerts are `critical`
- Single-event "noisy" alerts (log_error, pod_pending, packet_loss, container_restart) — if kept at all — have thresholds raised above 1

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

- **Raising thresholds without removing dead alerts.** If `log_error_any` shouldn't exist at all, raising its threshold from 1 to 10 doesn't fix it — you still have an unactionable alert, just one that fires less often. Sometimes the right answer is delete.
- **Keeping everything as critical.** It feels safer ("I don't want to miss anything") but it's the opposite — it guarantees real critical alerts get ignored alongside the noise.
- **Setting one global threshold for everything.** CPU and disk and response time and SSL all need different thresholds based on what's normal for that metric. Don't blanket everything at 80%.
- **Confusing alert deletion with metric deletion.** You can delete the *alert* on packet loss without deleting the *metric* — keep collecting the data, just stop paging on it. The metric still appears on dashboards for diagnostic use.
- **No runbooks.** This lab doesn't enforce it, but in production every critical alert should link to a runbook. Otherwise the on-call engineer is reverse-engineering the system at 3 AM.
- **Not reviewing alerts on a cadence.** Alerts decay — what was true six months ago may be wrong now. A monthly review of "which alerts fired, which were actionable, which were noise" keeps the configuration honest.
