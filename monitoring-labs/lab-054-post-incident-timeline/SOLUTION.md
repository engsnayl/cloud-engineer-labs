# Solution Walkthrough — Post-Incident Timeline Reconstruction

## The Problem

A major incident occurred overnight — payment processing was down for approximately 50 minutes. The CTO wants a full post-incident report. Four log files across different services tell the story of what happened. The task is to read the logs, reconstruct the timeline, identify the root cause, and write a comprehensive post-incident report.

The root cause: **disk space ran out due to PostgreSQL WAL file accumulation**, which caused the database to shut down, which caused the payment API to return 503 errors.

## Thought Process

When reconstructing a post-incident timeline, an experienced engineer:

1. **Gathers all log sources** — collect logs from every system involved: infrastructure, application, notification, and resolution. Each tells part of the story.
2. **Builds a chronological timeline** — sort all events by timestamp across all log sources. The order of events reveals the cascade.
3. **Identifies the root cause** — follow the chain backward from the symptom (payment failures) to the cause (database down) to the root cause (disk full from WAL files).
4. **Documents impact** — how long was the outage, which services were affected, how many requests failed.
5. **Writes action items** — concrete steps to prevent this from happening again.

## Step-by-Step Solution

### Step 1: Read all four log files

```bash
# Infrastructure logs — shows the disk filling up
cat /var/log/infra/system.log

# Payment API logs — shows the application impact
cat /var/log/app/payment-api.log

# Notification service logs — shows how alerting worked
cat /var/log/app/notification-service.log

# Resolution logs — shows how the incident was resolved
cat /var/log/infra/resolution.log
```

**What this does:** Each log file captures a different perspective:

- **system.log**: Disk usage climbed from 78% → 85% → 95%. PostgreSQL crashed because it couldn't write WAL files. Systemd tried to restart postgres but failed because disk was still full.
- **payment-api.log**: After postgres died, the payment API couldn't connect to the database. It retried 3 times, then started returning 503s. Over the next 10 minutes, 157 then 312 requests failed.
- **notification-service.log**: The alerting system detected the high error rate and sent a PagerDuty alert (after one rate-limit retry). The on-call engineer acknowledged at 02:25.
- **resolution.log**: The engineer found pg_wal consuming 45GB, ran pg_archivecleanup, freed disk space, restarted postgres, and confirmed recovery. Added WAL cleanup cron job.

### Step 2: Build the chronological timeline

From the logs, the timeline is:

| Time | Event | Source |
|------|-------|--------|
| 01:45 | Disk at 78% (normal monitoring) | system.log |
| 01:55 | Disk at 85% — warning level | system.log |
| 02:00 | Disk at 95% — CRITICAL | system.log |
| 02:00:15 | PostgreSQL FATAL: No space left on device (WAL write failed) | system.log |
| 02:00:16 | Database system shut down | system.log |
| 02:00:18 | Payment API: database connection failed | payment-api.log |
| 02:00:19-31 | Payment API retries (3 attempts, all failed) | payment-api.log |
| 02:00:32 | Payment API starts returning 503 to clients | payment-api.log |
| 02:00:35 | PostgreSQL restart attempt fails (disk still full) | system.log |
| 02:01:00 | Systemd gives up restarting postgresql | system.log |
| 02:05:00 | 157 failed requests in 5 minutes | payment-api.log |
| 02:10:00 | 312 failed requests in 5 minutes; alert triggered | payment-api.log, notification |
| 02:10:06 | PagerDuty alert sent successfully | notification-service.log |
| 02:25:00 | On-call engineer acknowledges alert | notification-service.log |
| 02:30:00 | Engineer begins investigating | resolution.log |
| 02:35:00 | Root cause found: pg_wal = 45GB | resolution.log |
| 02:40:00 | Running pg_archivecleanup | resolution.log |
| 02:45:00 | Disk back to 52% | resolution.log |
| 02:50:00 | PostgreSQL restarted, accepting connections | resolution.log |
| 02:50:10 | Payment API: database connection restored | resolution.log |
| 02:55:00 | Circuit breaker closed, normal operations | resolution.log |
| 04:30:00 | WAL archival cron job set up | resolution.log |

### Step 3: Write the post-incident report

```bash
cat > /tmp/post-incident-report.txt << 'EOF'
# Post-Incident Report: Payment Processing Outage
# Date: 2024-01-15
# Duration: ~50 minutes (02:00 - 02:50)
# Severity: SEV-1

## Summary
Payment processing was unavailable for approximately 50 minutes due to a
PostgreSQL database failure caused by disk space exhaustion. The /data
partition filled up because old WAL (Write-Ahead Log) files were not being
cleaned up, eventually consuming 45GB. When the disk reached 95% capacity,
PostgreSQL could not write new WAL segments and shut down, causing the
payment API to return 503 errors to all clients.

## Timeline

- 01:45 — Disk monitoring reports /data at 78% (normal)
- 01:55 — Disk reaches 85% — warning threshold crossed
- 02:00 — Disk reaches 95% — CRITICAL threshold
- 02:00:15 — PostgreSQL FATAL error: "could not write to file pg_wal/... No space left on device"
- 02:00:16 — PostgreSQL database system shuts down
- 02:00:18 — Payment API loses database connection, begins retry sequence
- 02:00:32 — Payment API exhausts retries, starts returning 503 to clients
- 02:01:00 — Systemd gives up restarting PostgreSQL (disk still full)
- 02:05:00 — 157 failed payment requests in the last 5 minutes
- 02:10:00 — 312 failed requests; PagerDuty alert triggered and sent
- 02:25:00 — On-call engineer acknowledges the alert
- 02:30:00 — Engineer begins investigation on database server
- 02:35:00 — Root cause identified: pg_wal directory consuming 45GB
- 02:40:00 — pg_archivecleanup executed to remove old WAL files
- 02:45:00 — Disk usage drops to 52%
- 02:50:00 — PostgreSQL restarted successfully, payment API recovers
- 02:55:00 — Circuit breaker closes, normal operations resume
- 04:30:00 — WAL archival cron job configured to prevent recurrence

## Root Cause
PostgreSQL WAL (Write-Ahead Log) files were accumulating on the /data
partition without being cleaned up. WAL files are created during every
database write operation and are essential for crash recovery and replication.
However, without an archival or cleanup process, old WAL files accumulated
to 45GB, filling the 95% of the partition. When PostgreSQL attempted to write
a new WAL segment, the "No space left on device" error caused a fatal
shutdown.

## Impact
- Payment processing unavailable for ~50 minutes (02:00 - 02:50)
- Estimated 469+ failed payment requests (157 in first 5 min + 312 in next 5 min + continued failures)
- All payment API clients received HTTP 503 errors
- Other services (not dependent on PostgreSQL) were unaffected
- No data loss — PostgreSQL WAL ensures crash consistency

## Resolution
1. Identified pg_wal directory as the space consumer (45GB)
2. Ran pg_archivecleanup to safely remove old WAL files
3. Disk usage dropped from 95% to 52%
4. Restarted PostgreSQL — database accepted connections
5. Payment API automatically reconnected and resumed processing

## Action Items to Prevent Recurrence
1. **Automated WAL cleanup** — Configure pg_archivecleanup as a cron job to
   remove WAL files older than 24 hours (DONE — implemented at 04:30)
2. **Better disk alerts** — Add warning alert at 70% and critical at 85%
   (currently only alerts at 95%, which is too late)
3. **WAL archival to S3** — Configure continuous WAL archival to S3 for
   disaster recovery, which also removes local files after upload
4. **Disk usage monitoring per directory** — Add monitoring for pg_wal
   directory size specifically, not just overall partition usage
5. **Database connection circuit breaker** — Payment API circuit breaker
   took 25 minutes to open; tune it to open faster on database failures
6. **Faster alert response** — 15 minutes from alert to acknowledgment.
   Review on-call escalation policies
EOF
```

**What this does:** Creates a comprehensive post-incident report that follows the standard format used by companies like Google, Amazon, and Netflix. It includes a clear summary, a chronological timeline with timestamps from the actual logs, root cause analysis (WAL accumulation → disk full → postgres crash), quantified impact (50 minutes downtime, 469+ failed requests), and concrete action items to prevent recurrence.

### Step 4: Validate

```bash
# Check report exists
test -f /tmp/post-incident-report.txt && echo "Report exists"

# Check for root cause keywords
grep -qi "disk\|WAL\|space" /tmp/post-incident-report.txt && echo "Root cause identified"

# Check for timeline
grep -qi "02:00\|timeline" /tmp/post-incident-report.txt && echo "Timeline included"

# Check for action items
grep -qi "prevent\|action\|recurrence" /tmp/post-incident-report.txt && echo "Action items included"

# Check for impact
grep -qi "payment\|impact\|503" /tmp/post-incident-report.txt && echo "Impact documented"
```

## Docker Lab vs Real Life

- **Centralized logging:** In production, logs from all services are aggregated in Elasticsearch, CloudWatch, or Datadog. You wouldn't SSH into individual servers to read log files — you'd query a central logging system with timestamps and service filters.
- **Automated incident detection:** Production systems use AIOps platforms that correlate signals across services. The disk warning at 01:55 should have triggered automated remediation before the outage.
- **Blameless post-mortems:** The best post-incident processes focus on systemic improvements, not individual blame. "The monitoring didn't catch the trend" is better than "the engineer didn't check disk space."
- **SLA impact tracking:** Production incident reports include SLA/SLO impact. "This outage consumed 40% of our monthly error budget" quantifies the business impact.
- **Incident management tools:** Teams use tools like incident.io, FireHydrant, or PagerDuty Incident Response to automate timeline capture, stakeholder communication, and action item tracking.

## Key Concepts Learned

- **Read all log sources chronologically** — a single log file shows one perspective. Correlating timestamps across infrastructure, application, notification, and resolution logs reveals the full story.
- **Follow the cascade backward** — start with the symptom (503 errors), trace to the cause (database down), trace to the root cause (disk full from WAL files). The root cause is always the earliest trigger in the chain.
- **Quantify the impact** — "the site was slow" is vague. "50 minutes of payment downtime, 469+ failed requests" is specific and actionable.
- **Action items must prevent recurrence** — "be more careful" is not an action item. "Configure automated WAL cleanup cron job" is. Each action item should be specific, assignable, and measurable.
- **Detection time matters** — the disk was at 85% at 01:55 but didn't cross critical until 02:00. Better alerting at 70-80% would have given the team 30+ minutes to prevent the outage entirely.

## Common Mistakes

- **Only reading one log file** — the system.log shows the disk issue but not the application impact. The payment-api.log shows the failures but not the root cause. You need all sources.
- **Missing timestamps in the report** — "the database went down and then the API failed" isn't useful. "02:00:15 database FATAL, 02:00:18 API connection refused" tells the exact sequence.
- **Vague root cause** — "disk was full" is a symptom. "PostgreSQL WAL files accumulated to 45GB without cleanup" is the root cause. The root cause explains WHY the disk was full.
- **No action items** — identifying what happened without preventing recurrence means the same incident will happen again.
- **Action items without owners** — "improve monitoring" is vague. "Configure disk alert at 70% threshold — assigned to DevOps team, due Friday" gets done.
