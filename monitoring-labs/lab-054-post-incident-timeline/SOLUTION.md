# Solution Walkthrough — Lab 054: Post-Incident Timeline Reconstruction

## TLDR (in plain English)

Last night, payments stopped working for about 50 minutes. The cause turned out to be boring: the database server's disk filled up. PostgreSQL keeps a folder of "write-ahead log" files (`pg_wal`) that record every change made to the database. Nobody had set up a job to clean old ones out, so they piled up to 45GB. When the disk hit 95% full, PostgreSQL couldn't write a new log entry, panicked, and shut itself down. The payment API lost its database, retried three times, gave up, and started returning HTTP 503 errors to every customer trying to pay. The on-call engineer ran a built-in PostgreSQL tool (`pg_archivecleanup`) to delete the old log files, freed up the disk, restarted the database, and everything came back.

**Your job this morning** is to reconstruct that story from log files scattered around the box and write it up as a proper post-mortem — what happened, when, why, what we did about it, and how we stop it happening again.

---

## The Ticket

You arrive at your desk at 08:42 and find this:

> INCIDENT-MON-005 — Major outage overnight. Payment processing was unavailable for an extended period. CTO wants a full post-incident report by EOD.

That's it. No log locations, no service list, no idea what broke first. You weren't on call. You're starting from zero.

---

## How to Think About This — The Diagnostic Pathway

Before touching the keyboard, what's the order of operations for any incident reconstruction?

1. **Find the evidence.** I don't yet know which logs exist or where they live. First job: locate them.
2. **Read everything once, no analysis.** Get a feel for what services were involved before trying to draw conclusions.
3. **Find the earliest error.** Incidents cascade. The thing that broke first is usually the root cause; everything after it is symptoms.
4. **Build a single chronological timeline across all sources.** One log shows one perspective. Correlating timestamps across logs is what reveals the cascade.
5. **Trace the chain backward from symptom to root cause.** Customers saw 503s. Why? API couldn't reach DB. Why? DB shut down. Why? Disk full. Why? WAL files. **Why no cleanup?** ← that's the real root cause.
6. **Quantify impact.** How long? How many failed requests? Which services?
7. **Write action items that prevent recurrence**, not vague aspirations.

Every step below maps to one of these.

---

## Step 1: Find the logs (no, you don't know where they are)

Real incidents don't come with a map. The first command an engineer runs on an unfamiliar box is some flavour of "where do logs live around here?"

```bash
ls /var/log/
```

| Component | What it does |
|-----------|--------------|
| `ls` | List directory contents |
| `/var/log/` | The conventional location for log files on Linux. Almost every distro and almost every service writes here by default. |

**How would I know to look here?** Convention. On Linux, `/var/log/` is the standard logging directory — system logs (`/var/log/syslog`, `/var/log/auth.log`), application logs (`/var/log/nginx/`, `/var/log/postgresql/`), and bespoke service logs all live under this tree. If logs aren't here, the next places to check are `/opt/<service>/logs`, the service's working directory, or — in a containerised world — `docker logs <container>` or a centralised aggregator.

You'll see two directories: `app/` and `infra/`. Good — services have been organised into application logs and infrastructure logs. Now find every log file:

```bash
find /var/log -type f -name "*.log"
```

| Component | What it does |
|-----------|--------------|
| `find` | Recursively search for files matching criteria |
| `/var/log` | The directory to search from |
| `-type f` | Only match regular files (not directories or symlinks) |
| `-name "*.log"` | Only match files ending in `.log` |

You should see four files:

```
/var/log/infra/system.log
/var/log/infra/resolution.log
/var/log/app/payment-api.log
/var/log/app/notification-service.log
```

Four log sources. Each one is a single perspective. The full story comes from correlating them.

---

## Step 2: Read everything once, no analysis yet

Resist the urge to start drawing conclusions. First job is just to get a sense of what each log contains and what services are involved.

```bash
cat /var/log/infra/system.log
cat /var/log/infra/resolution.log
cat /var/log/app/payment-api.log
cat /var/log/app/notification-service.log
```

| Component | What it does |
|-----------|--------------|
| `cat` | Print file contents to the terminal. Short for "concatenate" — its original purpose was joining files, but printing one file is the most common use. |

After this pass, you should know:
- **system.log** — disk monitor and postgres events
- **payment-api.log** — payment API errors and request counts
- **notification-service.log** — alerting and PagerDuty
- **resolution.log** — what the on-call engineer did

Four services touched the incident: disk monitoring, postgres, payment API, alerting. Now you can start analysing.

---

## Step 3: Find the earliest error — the start of the cascade

In any cascading incident, the first error in time is almost always closest to the root cause. Everything after is downstream symptoms.

```bash
grep -h ERROR /var/log/infra/*.log /var/log/app/*.log | sort
```

| Component | What it does |
|-----------|--------------|
| `grep` | Search files for lines matching a pattern |
| `-h` | Suppress filename prefix in output (cleaner when sorting) |
| `ERROR` | The pattern to match — case-sensitive, matches the literal string `ERROR` |
| `/var/log/infra/*.log` | All log files in the infra directory |
| `/var/log/app/*.log` | All log files in the app directory |
| `\|` | Pipe — send output of `grep` as input to the next command |
| `sort` | Sort lines alphabetically. Because timestamps are in `YYYY-MM-DD HH:MM:SS` format, alphabetical sort is also chronological sort. |

**Why this works:** ISO 8601 timestamps (`2024-01-15 02:00:15`) sort lexicographically the same way they sort chronologically. This is the entire reason that format is the standard for log files — you can sort logs from a dozen different services with a plain `sort` and the output is in time order.

The very first ERROR line you'll see is:

```
2024-01-15 02:00:00 ERROR disk-monitor: /data partition at 95% usage - CRITICAL
```

That's the start of the cascade. **Disk hit 95% at 02:00 sharp.** Hold onto that timestamp.

---

## Step 4: Trace the cascade forward from the first error

Now read the lines immediately following 02:00:00 in each log, in order. The chain reveals itself:

| Time | Source | What happened |
|------|--------|---------------|
| 02:00:00 | system.log | Disk at 95% — CRITICAL |
| 02:00:15 | system.log | postgres: FATAL — could not write to `pg_wal/...` — No space left on device |
| 02:00:16 | system.log | postgres: database system is shut down |
| 02:00:18 | payment-api.log | Database connection failed |
| 02:00:32 | payment-api.log | All retries exhausted. Returning 503 to clients |

So the chain is: **disk full → postgres can't write WAL → postgres dies → API can't reach DB → 503s to customers.**

**At this point you have the symptom and you have the immediate cause, but you don't have the *root* cause yet.** The disk filled up — but *why* did the disk fill up? "Disk full" is what an alert says; "WAL files accumulated to 45GB without cleanup" is what an incident report says.

---

## Step 5: Find the root cause — what the on-call engineer discovered

Skip ahead to what the engineer found when they investigated. The clue is in `resolution.log`:

```bash
cat /var/log/infra/resolution.log
```

The key line:

```
2024-01-15 02:35:00 INFO engineer: Found: pg_wal directory consuming 45GB. Old WAL files not being cleaned up
```

There's your root cause. Not "disk full" — that's a symptom of the actual problem, which is **PostgreSQL WAL files accumulated unchecked to 45GB because no cleanup process existed.**

> **What's a WAL file?** Write-Ahead Log. Every change PostgreSQL makes to the database is first written to a WAL file before being applied to the actual data files. This is what makes postgres crash-safe — if the server dies mid-transaction, it can replay the WAL on startup and recover. WAL files keep getting created as the DB does work; old ones need to be either archived (sent to backup storage) or deleted by a cleanup process. Neither was configured here, so they piled up forever.

---

## Step 6: Pull out the resolution steps

`resolution.log` already documents what the engineer did. Read it as a sequence:

| Time | Action |
|------|--------|
| 02:30 | Engineer began investigating |
| 02:35 | Identified pg_wal as the disk hog (45GB) |
| 02:40 | Ran `pg_archivecleanup` to remove old WAL files |
| 02:45 | Disk dropped from 95% to 52% |
| 02:50 | Restarted postgres — accepted connections |
| 02:55 | Payment API circuit breaker closed — normal operations |
| 04:30 | Set up WAL archival cron job to prevent recurrence |

> **What's `pg_archivecleanup`?** A built-in PostgreSQL utility that safely removes WAL files that are no longer needed (i.e. ones that have already been replayed or archived). Safe to run while postgres is down. Comes with the postgres install, no extra package needed.

---

## Step 7: Quantify the impact

The CTO doesn't want "it was bad". They want numbers.

```bash
grep -i "failed requests" /var/log/app/payment-api.log
```

| Component | What it does |
|-----------|--------------|
| `grep` | Search for matching lines |
| `-i` | Case-insensitive match |
| `"failed requests"` | The exact phrase to find |

Output:

```
2024-01-15 02:05:00 WARN payment-api: 157 failed requests in last 5 minutes
2024-01-15 02:10:00 WARN payment-api: 312 failed requests in last 5 minutes
```

Plus everything from 02:10 to 02:50 that wasn't logged in 5-minute summaries. The conservative number to put in the report is **469+ failed requests** across the 50-minute outage window (02:00 → 02:50).

Duration: **02:00 → 02:50 = 50 minutes of downtime.** (Note: the ticket said 2.5 hours, which is wrong — engineer logs end at 04:30 because they were *finishing the prevention work*, not because the outage lasted that long. Worth flagging in the report.)

---

## Step 8: Write the post-incident report

Now you have everything you need. Write it up to `/tmp/post-incident-report.txt`.

```bash
cat > /tmp/post-incident-report.txt << 'EOF'
# Post-Incident Report: Payment Processing Outage
# Date: 2024-01-15
# Duration: ~50 minutes (02:00 - 02:50)
# Severity: SEV-1
# Author: <your name>, written 2024-01-15 morning

## Summary
Payment processing was unavailable for approximately 50 minutes due to a
PostgreSQL database failure caused by disk space exhaustion. The /data
partition filled up because old WAL (Write-Ahead Log) files were not being
cleaned up, eventually consuming 45GB. When the disk reached 95% capacity,
PostgreSQL could not write new WAL segments and shut down, causing the
payment API to return 503 errors to all clients.

Note: The original ticket cited a 2.5-hour outage (02:00 - 04:30). The
actual customer-facing outage was 50 minutes (02:00 - 02:50). The window
between 02:50 and 04:30 was the engineer implementing the prevention fix
(WAL archival cron) — not active downtime.

## Timeline

- 01:45 — Disk monitoring reports /data at 78% (normal)
- 01:55 — Disk reaches 85% — warning threshold crossed
- 02:00 — Disk reaches 95% — CRITICAL threshold breached
- 02:00:15 — PostgreSQL FATAL: "could not write to file pg_wal/... No space left on device"
- 02:00:16 — PostgreSQL database system shuts down
- 02:00:18 — Payment API loses database connection, begins retry sequence
- 02:00:32 — Payment API exhausts retries, starts returning 503 to clients
- 02:01:00 — Systemd gives up restarting PostgreSQL (disk still full)
- 02:05:00 — 157 failed payment requests in the last 5 minutes
- 02:10:00 — 312 failed requests; PagerDuty alert triggered and sent
- 02:25:00 — On-call engineer acknowledges the alert (15 min after page)
- 02:30:00 — Engineer begins investigation on database server
- 02:35:00 — Root cause identified: pg_wal directory consuming 45GB
- 02:40:00 — pg_archivecleanup executed to remove old WAL files
- 02:45:00 — Disk usage drops to 52%
- 02:50:00 — PostgreSQL restarted successfully; payment API recovers
- 02:55:00 — Circuit breaker closes; normal operations resume
- 04:30:00 — WAL archival cron job configured to prevent recurrence

## Root Cause
PostgreSQL WAL (Write-Ahead Log) files were accumulating on the /data
partition without any cleanup or archival process configured. WAL files
are created on every database write and are essential for crash recovery
and replication, but they must be either archived to backup storage or
deleted once they're no longer needed. Neither was configured on this
database server. Over time, WAL files accumulated to 45GB, which combined
with other partition usage pushed the disk to 95%. When PostgreSQL
attempted to write the next WAL segment, it received a "No space left on
device" error and shut down.

## Impact
- Payment processing unavailable for ~50 minutes (02:00 - 02:50)
- Estimated 469+ failed payment requests (157 + 312 in first two five-minute
  windows alone, with continued failures through the outage)
- All payment API clients received HTTP 503 errors
- Services not dependent on PostgreSQL were unaffected
- No data loss — PostgreSQL WAL ensures crash consistency

## Resolution
1. On-call engineer paged at 02:10, acknowledged at 02:25
2. Investigation began on database server at 02:30
3. Identified pg_wal directory as the space consumer (45GB) at 02:35
4. Ran pg_archivecleanup to safely remove old WAL files
5. Disk usage dropped from 95% to 52%
6. Restarted PostgreSQL — database accepted connections at 02:50:05
7. Payment API automatically reconnected; circuit breaker closed at 02:55

## Action Items to Prevent Recurrence
1. **Automated WAL cleanup** — pg_archivecleanup as a cron job, removing
   WAL files older than 24h. (DONE — implemented at 04:30)
2. **WAL archival to S3** — continuous WAL archival to S3 for point-in-time
   recovery; the upload step also removes local files automatically.
3. **Earlier disk alerts** — current alerting only fires at 95%. Add
   warning at 70% and critical at 85% to give the team 30+ minutes of
   runway before an outage becomes inevitable.
4. **Per-directory disk monitoring** — alert on pg_wal directory size
   specifically, not just overall partition usage. Would have caught this
   long before partition-level alerts fired.
5. **Tune circuit breaker** — payment API circuit breaker took until
   02:30 to OPEN (30 min after first failure). Should open within 1-2
   minutes of sustained DB failure to fail fast and reduce client load.
6. **Review on-call response time** — 15 minutes from page to ack is
   above target. Review escalation policy and on-call rotation health.
EOF
```

> **What's the `cat > file << 'EOF' ... EOF` thing?** It's a *heredoc*. Everything between the two `EOF` markers gets written to the file as-is. The single quotes around `'EOF'` matter — they tell bash not to interpret `$variables` or backticks inside the block, so you can paste literal content (including dollar signs and quotes) without escaping anything. Without the quotes, bash would try to expand `$variables` inside the heredoc.

---

## Step 9: Validate

```bash
bash /opt/validate.sh
```

…or however your lab tooling exposes it. Each check should pass.

| Check | What it's looking for |
|-------|------------------------|
| Report exists | File is present at `/tmp/post-incident-report.txt` |
| Substantive content | At least 20 lines (guards against trivial pass) |
| Root cause identified | Words like `disk`, `WAL`, `space` appear |
| Timeline included | Either the literal `02:00` or the word `timeline` appears |
| Impact documented | Words like `payment`, `503`, `failed` appear |
| Resolution described | Words like `restart`, `cleanup`, `archive` appear |
| Action items present | Words like `prevent`, `action`, `recurrence` appear |

---

## Docker Lab vs Real Life

- **Centralised logging.** In production, you wouldn't `cat` files on individual servers — you'd query a central system like Datadog, CloudWatch Logs, ELK, or Splunk with a time range and a service filter. The four log files in this lab represent four log streams in one of those systems.
- **Automated incident detection.** The disk warning at 01:55 should have triggered automated remediation (or at least a louder page) before the outage ever happened. AIOps platforms correlate signals across services to catch cascades earlier.
- **Blameless post-mortems.** Real post-mortems focus on systemic improvements, not individual blame. "The monitoring didn't catch the trend" is better than "the engineer didn't check disk space."
- **SLA/SLO impact.** Production reports include error budget impact: "This outage consumed 40% of our monthly error budget."
- **Incident management tools.** Teams use incident.io, FireHydrant, or PagerDuty Incident Response to automate timeline capture, stakeholder updates, and action item tracking. The thing you wrote by hand here is generated semi-automatically from the incident channel transcript.

---

## Key Concepts Learned

- **Find the evidence first.** No incident comes with a map. Knowing the conventions (`/var/log`, `find -name "*.log"`) is half the skill.
- **ISO 8601 timestamps sort lexicographically.** That's why `sort` works as a chronological sorter when log timestamps are formatted that way.
- **The first error in time is closest to the root cause.** Trace forward from there to see the cascade; trace backward from the symptom to confirm the chain.
- **"Disk full" is a symptom, "WAL files accumulated unchecked" is a cause.** Always ask "but why?" one more time than feels comfortable.
- **Quantify impact in numbers.** Duration, request count, customer count. Vague impact statements get vague action items.
- **Action items must be specific and assignable.** "Improve monitoring" is not an action item. "Add disk alert at 70% threshold, owned by DevOps, due Friday" is.

---

## Common Mistakes

- **Reading only one log file.** The system.log shows the disk issue but not the application impact. The payment-api.log shows the failures but not the cause. You need all sources, correlated.
- **Confusing symptom with root cause.** "Database went down" is a symptom. "WAL files weren't being cleaned up" is the cause.
- **Missing precise timestamps.** "The DB went down and then the API failed" is useless. "02:00:15 DB FATAL → 02:00:18 API connection refused" is precise.
- **Vague action items.** "Be more careful" is not an action item. "Configure pg_archivecleanup cron" is.
- **Trusting the ticket's numbers.** The ticket said 2.5 hours; the logs say 50 minutes of customer impact. Always verify against the evidence.
- **Forgetting to document what already worked.** The alerting did fire, the circuit breaker did engage, the on-call did respond. Note what worked as well as what didn't — it informs what *not* to change.
