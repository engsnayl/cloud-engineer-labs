# Solution Walkthrough — Application Throwing 500 Errors

## The Problem

The application is returning HTTP 500 errors intermittently. Not all requests fail — the `/api/users` endpoint works fine, but `/api/payments` fails when the database connection pool is exhausted. The pool has a maximum of 5 connections, and under load, the pool fills up and subsequent requests get a "connection pool exhausted" error.

The task is to investigate the logs, identify the root cause, and write an incident report documenting the findings.

## Thought Process

When investigating intermittent 500 errors, an experienced engineer checks:

1. **Which endpoints are failing?** — not all 500s are the same. Filter logs by endpoint to find the pattern. If `/api/users` works but `/api/payments` doesn't, the issue is specific to the payments path.
2. **What's the error message?** — look for the actual error in the logs, not just the status code. "Connection pool exhausted" points to a resource limit, not a code bug.
3. **Is it intermittent or consistent?** — intermittent failures that worsen under load suggest resource exhaustion (connection pools, memory, file descriptors). Consistent failures suggest configuration or code errors.
4. **Is the application still running?** — check the health endpoint to confirm the process hasn't crashed entirely.

## Step-by-Step Solution

### Step 1: Check the application logs for errors

```bash
# Inside the container
# Look for 500 errors specifically
docker logs lab050-app-500-errors 2>&1 | grep "500"

# Look for ERROR level messages
docker logs lab050-app-500-errors 2>&1 | grep "ERROR"
```

**What this does:** Filters the application logs to show only error entries. You'll see lines like:
```
ERROR 500 GET /api/payments - DatabaseError: connection pool exhausted (used: 6, max: 5)
```

This tells you the endpoint (`/api/payments`), the error type (`DatabaseError`), and the root cause (`connection pool exhausted` — 6 connections in use but the pool only allows 5).

### Step 2: Verify which endpoints are affected

```bash
# Check if /api/users works
curl -s http://localhost:8080/api/users
# Returns: {"users": []}  — works fine

# Check if /api/payments fails
curl -s http://localhost:8080/api/payments
# May return: {"error": "Internal Server Error"}

# Check health endpoint
curl -s http://localhost:8080/api/health
# Returns: OK
```

**What this does:** Confirms that the issue is isolated to `/api/payments`. The health endpoint still responds, so the application process is running — it's a resource problem, not a crash.

### Step 3: Identify the root cause

From the logs, the pattern is clear:

- `/api/payments` opens a database connection for each request
- The pool allows maximum 5 connections
- Under load, connections are acquired faster than they're released
- Once the pool is full (`used > max`), new requests fail with 500

The root cause is **database connection pool exhaustion** on the `/api/payments` endpoint.

### Step 4: Write the incident report

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
The database connection pool has a maximum of 5 connections. Under load, the
/api/payments endpoint acquires connections faster than they are released. When
all 5 connections are in use, subsequent requests receive a "connection pool
exhausted" error and return HTTP 500 to clients.

## Evidence
Application logs show:
  ERROR 500 GET /api/payments - DatabaseError: connection pool exhausted (used: 6, max: 5)

## Impact
- Payment processing is intermittently failing
- Approximately 15% of payment requests receive HTTP 500 errors
- Other endpoints (/api/users, /api/health) are not affected

## Recommended Fix
1. Increase the database connection pool size (e.g., max: 20)
2. Add connection timeouts so idle connections are returned to the pool
3. Implement request queuing or rate limiting on /api/payments
4. Add circuit breaker pattern to prevent cascading failures
5. Add monitoring/alerting on pool utilization before it hits 100%
EOF
```

**What this does:** Creates a structured incident report that documents everything needed for the team: what failed, why it failed, what evidence supports the finding, and what to do about it. The report identifies the specific endpoint, the database connection pool as the root cause, and recommends concrete fixes.

### Step 5: Validate

```bash
# Check report exists
test -f /tmp/incident-report.txt && echo "Report exists"

# Check report content
grep -qi "pool\|connection\|database" /tmp/incident-report.txt && echo "Root cause identified"
grep -qi "payment" /tmp/incident-report.txt && echo "Endpoint identified"

# Check app is still running
curl -s http://localhost:8080/api/health
```

## Docker Lab vs Real Life

- **APM tools:** In production, tools like Datadog APM, New Relic, or Jaeger trace each request through every service. You'd see the exact database query that timed out, not just the HTTP status code.
- **Connection pool monitoring:** Production databases expose pool metrics (active, idle, waiting connections). Grafana dashboards show pool utilization trending toward the limit before failures start.
- **Auto-scaling:** Cloud-native applications scale horizontally when load increases. Each instance has its own connection pool, so adding instances spreads the connection load.
- **PgBouncer / ProxySQL:** Production databases often use connection poolers that sit between the application and the database. They multiplex hundreds of application connections onto a smaller number of database connections.
- **Alerting on pool utilization:** Set up alerts at 70% pool utilization (warning) and 90% (critical). This gives the team time to respond before pool exhaustion causes 500 errors.

## Key Concepts Learned

- **Filter logs by severity and endpoint** — `grep "ERROR"` and `grep "500"` quickly isolate the problem from verbose application logs.
- **Database connection pool exhaustion is a common cause of intermittent 500s** — it only fails under load, works fine in testing, and affects specific code paths that use the database.
- **Always check the health endpoint** — confirms whether the application process is running. A running process with endpoint-specific failures is a different problem than a crashed process.
- **Incident reports should include evidence** — don't just say "database issue." Include the exact log line, the affected endpoint, the error message, and the recommended fix.
- **Root cause vs symptom** — the symptom is "500 errors." The root cause is "connection pool max is 5 and connections aren't released fast enough under load."

## Common Mistakes

- **Only looking at status codes** — "500 error" doesn't tell you anything. The log message "connection pool exhausted" tells you everything.
- **Restarting the application** — this temporarily fixes pool exhaustion (connections reset) but doesn't fix the root cause. The pool will fill up again under load.
- **Blaming the endpoint code** — the payments code may be correct. The issue is the pool size and connection lifecycle management, not the query logic.
- **Missing the intermittent pattern** — if you test with one request, it works. The bug only appears under concurrent load when the pool fills up.
- **Incident reports without recommended actions** — identifying the problem is half the job. The report should include concrete steps to prevent recurrence.
