# Solution Walkthrough — Memory Leak Detection

## The Problem

The application server's memory usage is growing steadily. It started fine but over time consumes more and more RAM. The OOM killer will eventually terminate processes, causing an outage. There are two Python processes running:

1. A **legitimate application** — a simple sleep loop that uses constant memory.
2. A **leaking "cache service"** — a Python process that continuously adds entries to a dictionary without ever removing them. Each entry is 10KB, added every 0.2 seconds. This is the memory leak.

The task is to identify which process is leaking, kill it (without killing the legitimate application), and write an incident report.

## Thought Process

When memory usage is growing on a server, an experienced engineer checks:

1. **Which process is consuming the most memory?** — use `ps aux --sort=-%mem` to rank processes by memory usage. Watch it over time to see which one is growing.
2. **Is the growth linear or spiky?** — linear growth suggests a leak (accumulating data without cleanup). Spikes suggest load-based behavior.
3. **Can you identify the leaking process?** — read `/proc/<pid>/cmdline` or use `ps` to see the process command. Identify what it does.
4. **Kill the right process** — PIDs are stored in files. Verify you're killing the leaker, not the legitimate app.

## Step-by-Step Solution

### Step 1: Check memory usage over time

```bash
# Watch memory usage in real time
watch -n 2 'ps aux --sort=-%mem | head -5'

# Or check the monitoring log
cat /var/log/monitoring/memory.log
```

**What this does:** `ps aux --sort=-%mem` lists processes sorted by memory usage (highest first). Running it repeatedly with `watch` shows which process is growing. The monitoring log (`memory.log`) records total memory usage every 5 seconds, showing the upward trend over time.

### Step 2: Identify the leaking process

```bash
# List Python processes with their memory usage
ps aux | grep python3

# Check memory of each process individually
ps -o pid,%mem,rss,cmd -p $(cat /tmp/leaky.pid)
ps -o pid,%mem,rss,cmd -p $(cat /tmp/legit-app.pid)
```

**What this does:** Shows the two Python processes and their memory consumption. The leaking process (PID stored in `/tmp/leaky.pid`) will have significantly higher RSS (Resident Set Size) than the legitimate app (PID in `/tmp/legit-app.pid`). The leaker's memory keeps growing because it builds a dictionary that never gets cleaned up.

### Step 3: Confirm which process is which

```bash
# Check what each process is doing
cat /proc/$(cat /tmp/leaky.pid)/cmdline | tr '\0' ' '
cat /proc/$(cat /tmp/legit-app.pid)/cmdline | tr '\0' ' '

# You can also check the process start commands
ps -fp $(cat /tmp/leaky.pid)
ps -fp $(cat /tmp/legit-app.pid)
```

**What this does:** Reads the command line of each process from `/proc`. The leaking process's code includes `cache = {}` with entries being added in a loop. The legitimate process is a simple `while True: time.sleep(60)` loop. This confirms which one to kill.

### Step 4: Kill the leaking process

```bash
# Kill the leaking process
kill $(cat /tmp/leaky.pid)

# Verify it's dead
kill -0 $(cat /tmp/leaky.pid) 2>/dev/null && echo "Still running" || echo "Killed"

# Verify the legitimate app is still running
kill -0 $(cat /tmp/legit-app.pid) 2>/dev/null && echo "Legit app OK" || echo "ERROR: Legit app killed!"
```

**What this does:** Sends SIGTERM to the leaking process using the PID stored in `/tmp/leaky.pid`. The `kill -0` check sends signal 0 (which doesn't actually kill anything) to test if the process exists. After killing the leaker, memory usage will stop growing. The legitimate application should still be running.

### Step 5: Write the incident report

```bash
cat > /tmp/incident-report.txt << 'EOF'
# Incident Report: Memory Leak on Application Server

## Summary
Steadily growing memory usage caused by a leaking cache service process.
Memory was trending upward linearly, risking an OOM kill within hours.

## Root Cause
A Python "cache service" process was continuously adding entries to an
in-memory dictionary without ever evicting or removing old entries. Each
entry was approximately 10KB, added every 0.2 seconds (~50 entries/second).
Over time, this caused unbounded memory growth.

## Identification
- Used `ps aux --sort=-%mem` to identify the top memory-consuming process
- Confirmed growing memory by watching RSS over time
- Identified the process as a cache service writing to a dict without cleanup
- Distinguished from the legitimate application which had stable memory usage

## Resolution
- Killed the leaking cache service process (PID from /tmp/leaky.pid)
- Verified the legitimate application was not affected
- Memory usage stabilized after killing the leaking process

## Impact
- Server memory was trending toward OOM kill
- If unchecked, the OOM killer would have terminated random processes,
  potentially including the legitimate application

## Prevention
1. Implement cache eviction (TTL, LRU, max size) in the cache service
2. Set memory limits (cgroups/container limits) per process
3. Add memory usage alerts at 70% and 90% utilization
4. Monitor per-process memory trends, not just total system memory
5. Use proper caching libraries (Redis, Memcached) instead of in-process dicts
EOF
```

**What this does:** Documents the incident for the team. The report identifies the root cause (unbounded dictionary growth), explains how the leak was found, and recommends prevention measures. The key insight is that the cache service needs eviction logic — a cache that never removes entries is just a memory leak.

### Step 6: Validate

```bash
# Check leaky process is killed
! kill -0 $(cat /tmp/leaky.pid) 2>/dev/null && echo "Leaker killed"

# Check legit app still running
kill -0 $(cat /tmp/legit-app.pid) 2>/dev/null && echo "Legit app running"

# Check report exists
test -f /tmp/incident-report.txt && echo "Report created"
```

## Docker Lab vs Real Life

- **Container memory limits:** In production, containers have memory limits (`docker run --memory=512m` or Kubernetes resource limits). When a container exceeds its limit, it's killed rather than affecting the host.
- **Memory profiling tools:** Python has `tracemalloc`, `objgraph`, and `memory_profiler` for identifying exactly which objects are consuming memory. In production, take heap dumps rather than guessing.
- **Redis/Memcached for caching:** Production applications use external cache stores (Redis, Memcached) instead of in-process dictionaries. External caches have built-in eviction policies (LRU, TTL, max-memory).
- **OOM killer behavior:** Linux OOM killer scores processes and kills the one with the highest score (usually the biggest memory consumer). This can kill your important application if a different process is leaking. Container limits prevent this by isolating the blast radius.
- **Prometheus + Grafana monitoring:** Track `process_resident_memory_bytes` per process. Set alerts on memory growth rate, not just absolute thresholds.

## Key Concepts Learned

- **`ps aux --sort=-%mem` identifies memory hogs** — sort processes by memory usage to quickly find the top consumers. Watch over time to see which one is growing.
- **RSS (Resident Set Size) is the metric that matters** — it shows how much physical RAM a process actually uses, not virtual memory (which can be misleading).
- **Kill the right process** — always verify which process you're killing. Use `/proc/<pid>/cmdline` or `ps -fp <pid>` to confirm. Killing the wrong process causes a different outage.
- **Memory leaks are unbounded growth** — a process that uses a lot of memory isn't necessarily leaking. A leak is when memory grows over time without bound. The trend matters more than the absolute value.
- **Caches need eviction policies** — any in-memory cache that grows without a size limit or TTL is a memory leak waiting to happen.

## Common Mistakes

- **Killing the wrong process** — two Python processes look similar. Check the PID, command line, and memory trend before killing.
- **Only checking total system memory** — `free -m` shows total usage but doesn't tell you which process is responsible. Always use per-process tools.
- **Restarting the server instead of investigating** — a restart temporarily fixes the memory issue, but the leak starts again immediately. Identify and fix the root cause.
- **Not setting up prevention** — fixing the immediate issue without adding memory limits, monitoring, and eviction policies means the same leak will happen again.
- **Confusing high memory with a leak** — a process using 2GB is fine if it's stable. A process growing from 50MB to 500MB over 6 hours is a leak, even though 500MB isn't "high."
