# Solution Walkthrough — Alert Fatigue Triage

## The Problem

The on-call engineer is receiving 200+ alerts per day, and 95% are non-actionable noise. Real incidents are being missed because the team has learned to ignore alerts. The alert configuration (`/opt/monitoring/alerts.json`) has **two systemic issues**:

1. **Absurd thresholds** — every alert triggers on normal operating conditions. CPU alert at 1%, memory at 10%, response time at 10ms, SSL cert expiry at 365 days. These fire constantly because normal systems always exceed these thresholds.
2. **Everything is "critical"** — all 10 alerts are severity "critical," which means the on-call engineer gets paged for trivially normal conditions. There's no distinction between "the site is down" and "CPU is at 3%."

The task is to create a fixed alert configuration at `/opt/monitoring/alerts-fixed.json` with reasonable thresholds, appropriate severity levels, and fewer than 10 total alerts.

## Thought Process

When triaging noisy alerts, an experienced engineer asks for each alert:

1. **Is this actionable?** — would an on-call engineer need to do something when this fires? "CPU at 3%" requires no action. "CPU at 95% for 10 minutes" does.
2. **What's a reasonable threshold?** — based on industry standards and the application's normal operating range. CPU warning at 70-80%, critical at 90%. Response times depend on the application.
3. **What severity should it be?** — critical = wake someone up immediately. Warning = review during business hours. Info = dashboard only, no notification.
4. **Can alerts be consolidated?** — instead of 10 alerts that each fire on minor conditions, have 5-7 well-tuned alerts that fire only when something needs attention.

## Step-by-Step Solution

### Step 1: Review the current (broken) alert configuration

```bash
cat /opt/monitoring/alerts.json
```

```json
{
  "alerts": [
    {"name": "cpu_above_1_percent", "threshold": 1, "severity": "critical"},
    {"name": "memory_above_10_percent", "threshold": 10, "severity": "critical"},
    {"name": "disk_above_50_percent", "threshold": 50, "severity": "critical"},
    {"name": "http_5xx_any", "threshold": 1, "severity": "critical"},
    {"name": "response_time_above_10ms", "threshold": 10, "severity": "critical"},
    {"name": "container_restart", "threshold": 1, "severity": "critical"},
    {"name": "ssl_cert_expiry_365d", "threshold": 365, "severity": "critical"},
    {"name": "log_error_any", "threshold": 1, "severity": "critical"},
    {"name": "network_packet_loss_any", "threshold": 0.01, "severity": "critical"},
    {"name": "pod_pending_1s", "threshold": 1, "severity": "critical"}
  ]
}
```

**What this does:** Shows why there are 200+ alerts per day. Every threshold is set at a level that normal systems constantly exceed. CPU at 1% fires on any running server. A single log ERROR line pages the on-call. An SSL cert that expires in 11 months triggers a critical alert.

### Step 2: Review the alert log to see the noise

```bash
cat /opt/monitoring/alert-log.txt
```

**What this does:** Shows the actual alert history — "CPU at 3%," "Memory at 45%," "Response 42ms." These are all completely normal values that shouldn't trigger any alert, let alone a critical page.

### Step 3: Create the fixed alert configuration

```bash
cat > /opt/monitoring/alerts-fixed.json << 'EOF'
{
  "alerts": [
    {
      "name": "cpu_high",
      "threshold": 80,
      "severity": "warning",
      "description": "CPU usage above 80% — investigate if sustained"
    },
    {
      "name": "cpu_critical",
      "threshold": 95,
      "severity": "critical",
      "description": "CPU usage above 95% — immediate action required"
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
      "description": "Disk usage above 95% — immediate action needed"
    },
    {
      "name": "http_5xx_rate",
      "threshold": 5,
      "severity": "critical",
      "description": "5xx error rate above 5% of total requests"
    },
    {
      "name": "response_time_high",
      "threshold": 2000,
      "severity": "warning",
      "description": "P95 response time above 2 seconds"
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

**What this does:** Creates a new alert configuration with these improvements:

- **CPU**: Warning at 80%, critical only at 95%. Normal CPU (3-50%) doesn't trigger anything.
- **Memory**: Warning at 85%. Only investigate if it's genuinely high.
- **Disk**: Warning at 85%, critical at 95%. Disk at 62% is normal — don't alert.
- **HTTP 5xx**: Alert on error *rate* (5% of requests), not individual errors. A single 500 is normal; 5% of all traffic returning 500 is a problem.
- **Response time**: Warning at 2000ms (2 seconds), not 10ms. 42ms is excellent performance.
- **SSL cert**: Warning at 30 days, not 365. A cert expiring in 11 months doesn't need attention.
- **Removed alerts**: Individual container restarts, single log errors, trivial packet loss, and 1-second pod pending are removed. These are noise, not actionable signals.
- **Mixed severities**: Only genuinely urgent conditions are "critical." Everything else is "warning" for business-hours review.

### Step 4: Validate the fix

```bash
# Check file exists
test -f /opt/monitoring/alerts-fixed.json && echo "Config exists"

# Check CPU threshold
python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
for a in data['alerts']:
    print(f\"{a['name']}: threshold={a['threshold']}, severity={a['severity']}\")
"

# Check severity variety
python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
severities = set(a['severity'] for a in data['alerts'])
print(f'Severities used: {severities}')
print(f'Alert count: {len(data[\"alerts\"])}')
"
```

## Docker Lab vs Real Life

- **PagerDuty/OpsGenie integration:** Production alert routing uses services like PagerDuty. Critical alerts page the on-call engineer immediately. Warnings create tickets for business-hours review. Info alerts go to dashboards only.
- **Alert grouping and deduplication:** When a server has high CPU AND high memory AND slow responses, you want ONE alert (the root cause), not three. Tools like Alertmanager group related alerts.
- **Runbooks:** Every critical alert should link to a runbook that explains what to check and how to fix it. This reduces mean time to resolution and helps less experienced on-call engineers.
- **SLO-based alerting:** Instead of threshold-based alerts, modern teams use SLO (Service Level Objective) burn rate alerts. "We're burning through our error budget 10x faster than normal" is more actionable than "CPU is high."
- **Alert review cadence:** Schedule monthly alert reviews. Look at which alerts fired, which were actionable, and which were noise. Continuously tune thresholds based on real data.

## Key Concepts Learned

- **Thresholds must reflect normal operating conditions** — set thresholds above the normal range, not at the floor. If CPU normally runs at 20-40%, alerting at 1% is pure noise.
- **Not everything is critical** — critical means "wake someone up at 3 AM." Warning means "look at this during business hours." Info means "visible on dashboard." Use severity levels to match urgency.
- **Alert on rates, not individual events** — a single 500 error is normal. 5% of all traffic returning 500 is an incident. Rate-based alerts reduce noise dramatically.
- **Fewer, better alerts beat many noisy alerts** — 8 well-tuned alerts that only fire on real issues are infinitely more valuable than 200 alerts per day that get ignored.
- **Alert fatigue kills incident response** — when the team ignores alerts because 95% are noise, the 5% that are real incidents get missed too. Tuning alerts is a safety issue.

## Common Mistakes

- **Setting thresholds too low "just in case"** — this creates noise. A threshold should fire when action is needed, not when something is slightly above normal.
- **Making everything critical** — if everything is critical, nothing is. Reserve critical for conditions that require immediate human intervention.
- **Alerting on individual events instead of rates** — one container restart is normal (OOM, health check failure, rolling update). 10 restarts in 5 minutes is a problem.
- **Not removing obsolete alerts** — as systems change, alerts become irrelevant. Review and remove alerts that no longer match the architecture.
- **Not having runbooks** — an alert without a runbook means the on-call engineer has to figure out what to do from scratch at 3 AM. Every alert should link to "here's what to check and how to fix it."
