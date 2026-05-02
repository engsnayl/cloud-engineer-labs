# Lab 051 — Memory Leak Detection

## TLDR (Plain English)

**What's wrong:** A server's memory usage keeps climbing and won't stop. Eventually the system will run out of RAM and the OOM killer will start terminating processes at random — possibly the wrong ones — causing an outage. Two Python processes are running on the box, and one of them is the culprit. The other is doing its job correctly and must not be touched.

**Why it's happening:** One of the Python processes is acting as a "cache" — but it's a cache that only ever adds entries and never removes them. Every fifth of a second it writes another 10KB blob into a dictionary in memory. The dictionary just grows forever. That's not really a cache, that's a memory leak with a misleading name.

**How we fix it:**
1. Confirm the symptom — is memory really climbing, or is the ticket stale?
2. Rank processes by memory consumption to find the heaviest one.
3. *Watch* the suspect grow over 30-60 seconds — high memory isn't the same as a leak; growth is what makes it a leak.
4. Confirm *which* process is which — kill the wrong one and we cause a different outage.
5. Kill the leaker.
6. Verify the legitimate app survived and memory has stabilised.
7. Write the incident report so the next person on call understands what happened.

The skill being practised here is **diagnostic discipline under time pressure**. The ticket gives us a deadline ("OOM in 2 hours") and two suspects. We can't just `kill -9` the heaviest Python process and hope — we need to *prove* which one is leaking before pulling the trigger.

---

## The Ticket

You're on call. This lands in your queue:

> **INCIDENT-MON-002**: Memory usage trending up linearly. Server starts at 30% memory, now at 75% after 6 hours. OOM kill expected within 2 hours. Find the leaking process.

That's it. No process names, no PIDs, no further context. You have a container called `lab051-memory-leak-detection` and a deadline.

---

## Real-Time Walkthrough

### Step 1: Get on the box and confirm the symptom

Before doing anything clever, confirm the ticket is telling the truth. Tickets are wrong all the time — maybe memory plateaued an hour ago and the alerter is stale.

```bash
docker exec -it lab051-memory-leak-detection bash
```

Once inside, the first command is always the same: get a snapshot of the system.

```bash
free -m
```

| Component | What it does |
|---|---|
| `free` | Reports memory usage |
| `-m` | Display values in megabytes (more readable than bytes) |

You'll see total RAM, used, free, and available. This is a snapshot — one moment in time. It tells you the *current* state but nothing about the *trend*. That matters: a server using 75% of memory might be fine if it's been at 75% for a year. A server at 75% that was at 30% six hours ago is on fire.

To confirm the trend, we need history. Most production systems have this in Prometheus/Grafana/CloudWatch. In this lab, there's a monitoring log:

```bash
cat /var/log/monitoring/memory.log
```

You'll see timestamped memory readings.

> ### ⚠️ Real-World Gotcha #1 — When the system view doesn't match the ticket
>
> **Don't be surprised if `free -m` shows ~30% memory and the monitoring log shows readings bouncing in a tight band rather than climbing.** This is exactly what a freshly-started lab looks like — and it mirrors a real-world scenario that catches engineers out constantly.
>
> The leaker accumulates ~3 MB per minute. If the lab has only been running a few minutes, total system memory has barely moved. The leak is real, but it hasn't accumulated enough to show up at the *system* level yet.
>
> **The lesson:** system-level metrics (`free -m`, total memory percentage) are too coarse to spot a slow leak in its early stages. By the time `free -m` shows a problem, the leak has already been running for hours. **Per-process metrics catch leaks earlier than system-wide metrics.**
>
> If the system view looks calm but the ticket says there's a leak, **don't conclude the ticket is wrong**. Zoom in to per-process before forming a verdict.

**Why we did this first:** Real engineers don't trust tickets blindly. Confirming the symptom in 30 seconds is cheap; investigating a non-issue for an hour is expensive.

---

### Step 2: Rank processes by memory consumption

Memory may or may not be visibly climbing yet at the system level. Either way, we need to find *what* is consuming it. The standard tool for this:

```bash
ps aux --sort=-%mem | head -10
```

| Component | What it does |
|---|---|
| `ps` | Lists running processes |
| `aux` | `a` = all users, `u` = user-friendly format with %CPU/%MEM, `x` = include processes without a terminal |
| `--sort=-%mem` | Sort by memory column. The `-` means descending (highest first) |
| `\| head -10` | Show only the top 10 lines so we don't drown in output |

The output has columns including `%MEM` (percentage of system memory) and `RSS` (Resident Set Size — actual physical RAM in KB). Look at the top of the list.

**What you're looking for:** the process at the top with growing RSS. In this lab, two `python3` processes will appear. One will have noticeably higher %MEM and RSS than the other. That's our prime suspect — but we don't kill anything yet.

> ### 💡 Real-World Insight #2 — `ps aux` may have already given you the answer
>
> Look at the COMMAND column carefully. The leaker in this lab was started with `python3 -c "..."` — meaning the entire Python script is *inline* in the command. `ps aux` shows it directly:
>
> ```
> PID 9 ... python3 -c  import time cache = {} counter = 0 while True:     cache[f'session_{counter}'] = 'x' * 10240 ...
> ```
>
> **You can read the actual leak code right there in the `ps` output.** The "cache that never evicts" is visible at a glance. You don't need `/proc/<PID>/cmdline` for this — you've already got it.
>
> This is common when investigating ad-hoc scripts, cron jobs, kubectl exec one-liners, or anything started with `python3 -c`, `bash -c`, etc. In those cases, `ps aux` is enough.
>
> **When you DO need `/proc/<PID>/cmdline`:** when the process was started with a script file (e.g. `python3 myservice.py`). Then `ps` shows you the script name, not the contents. To know what the code does, you'd need to read the script file or check the deployment manifest.

---

### Step 3: Watch the suspect grow

A process using a lot of memory isn't necessarily leaking. A database might legitimately use 8GB. To confirm a *leak*, we need to see memory **growing over time** for that specific process.

```bash
watch -n 2 'ps aux --sort=-%mem | head -5'
```

| Component | What it does |
|---|---|
| `watch` | Runs a command repeatedly and shows the output |
| `-n 2` | Refresh every 2 seconds |
| `'ps aux --sort=-%mem \| head -5'` | The command to repeat — single quotes so the shell doesn't expand it before `watch` gets it |

> ### ⏱️ How long should you watch?
>
> **30-60 seconds is enough.** The instinct is to stare at `watch` for 10 minutes "to be sure," but that's wasted time. If a process is growing visibly within a minute, you've got your evidence. If it's not growing in a minute, either it's not leaking or the leak is so slow you'd find it via long-term monitoring (Prometheus over hours), not by watching a terminal.
>
> The diagnostic signature you're looking for is unambiguous when it's there: one process's RSS ticking upward every refresh, others holding steady. Two data points showing growth = enough to act.

You should see the RSS column for one of the Python processes ticking upward visibly. The other process's RSS stays flat. That's the signature of a leak: **unbounded linear growth in one process's memory while others are stable**.

A typical observation: leaker grows from ~17 MB to ~23 MB in 2 minutes (~3 MB/min). This matches the code's behaviour exactly: 10 KB × 5 inserts/sec × 60 sec = ~3 MB/min. **The numbers fit the source.** That's the kind of consistency that lets you commit to a kill.

Press `Ctrl+C` to exit `watch`.

**Why we watched rather than relied on a single snapshot:** A snapshot can't distinguish "uses a lot" from "leaks a lot." Without the trend, we'd be guessing.

---

### Step 4: Confirm process identity (when needed)

In this lab, Step 2's `ps aux` already revealed the leaker's source code. You're done identifying. Skip to Step 5.

But because real production won't always be that kind, here's what to do when `ps aux` shows you a script name and nothing more:

```bash
ps aux | grep python3 | grep -v grep
```

| Component | What it does |
|---|---|
| `ps aux` | All processes |
| `\| grep python3` | Filter to only lines containing "python3" |
| `\| grep -v grep` | Exclude the `grep python3` command itself from the results (`-v` means invert) |

Now you have the PIDs. To work out what each one is doing, look at its command line via `/proc`:

```bash
cat /proc/<PID>/cmdline | tr '\0' ' '; echo
```

| Component | What it does |
|---|---|
| `/proc/<PID>/cmdline` | A virtual file the kernel exposes containing the exact command that started the process |
| `tr '\0' ' '` | The cmdline file separates arguments with null bytes (`\0`); translate them to spaces so it's readable |
| `; echo` | Add a newline at the end (cmdline doesn't end with one) so the prompt isn't on the same line |

For a script-based service, this typically gives you the path to the script. You'd then read the script file (`cat /path/to/script.py`) or — more commonly in production — pull up the deployment manifest, the GitHub repo, or whatever source-of-truth tells you what code is running.

**Why we mention this even when not needed today:** the lab is a teaching environment. Real production processes are rarely started with inline `-c` flags. The `/proc` skill is useful in its own right and worth knowing.

---

### Step 5: Kill the leaker

```bash
kill <PID-of-leaker>
```

`kill` sends SIGTERM by default, which asks the process to shut down cleanly. For a runaway Python loop this is enough; we don't need `kill -9` (SIGKILL) unless SIGTERM is ignored.

> ### ⚠️ Real-World Gotcha #3 — `kill -0` can be misleading (PID recycling and zombies)
>
> The classic verification pattern is:
>
> ```bash
> kill -0 <PID>
> ```
>
> `kill -0` sends signal 0 (a no-op) and returns success if the PID exists, error if it doesn't. The intent: "is this process alive?" In practice, it can lie to you in two ways.
>
> **Lie #1 — PID recycling.** Linux reuses PIDs aggressively, especially in containers with few processes. The kernel can assign your dead process's PID to a new short-lived process within seconds. `kill -0` says "alive!" but it's a different process entirely.
>
> **Lie #2 — Zombies (`<defunct>`).** When a process dies, the kernel keeps a tiny entry in the process table (PID, exit code, resource usage) until the *parent* process calls `wait()` to "reap" it. If the parent never does, the dead process stays as `<defunct>` forever. `kill -0` says "alive!" but the process is functionally dead — no CPU, no memory, just a corpse waiting for the funeral.
>
> Zombies are especially common in Docker. Container PID 1 is often something simple like `tail -f /dev/null` that doesn't reap children. In production this is solved with `tini` (`docker run --init` or `init: true` in compose). In this lab, the leaker becomes a zombie after `kill` because PID 1 doesn't reap.
>
> **The reliable check is `ps`, which shows process *state*:**
>
> ```bash
> ps -p <PID>
> ```
>
> If the COMMAND column shows `<defunct>`, it's a zombie — dead, not running. If the entry is missing entirely, it's gone. If it shows the original command, it's still alive. Process state codes:
>
> | State | Meaning |
> |---|---|
> | `R` | Running |
> | `S` | Sleeping (waiting for I/O, signal, etc.) — most processes most of the time |
> | `D` | Uninterruptible sleep (usually disk I/O) — alive |
> | `Z` | Zombie — dead, parent hasn't reaped |
> | `T` | Stopped (e.g. SIGSTOP) |
>
> **For "is this thing actually running?" use `ps`, not `kill -0`.**

So to verify the kill:

```bash
ps -p <PID-of-leaker>
```

Either no output (PID gone) or `<defunct>` (zombie) means the process is dead. Both are wins.

Then verify the legit app is **still alive** and *not* a zombie:

```bash
ps -p <PID-of-legit-app>
```

You should see the original `python3 -c ...sleep(60)...` command, not `<defunct>` and not empty.

**Why we verified both:** "I killed something" is not the same as "I killed the right thing and only the right thing." Two checks, two confirmations.

---

### Step 6: Confirm the bleed has stopped

Pull up `watch` again and check that memory has stabilised:

```bash
watch -n 2 'ps aux --sort=-%mem | head -5'
```

Or check the monitoring log:

```bash
tail -20 /var/log/monitoring/memory.log
```

The numbers should now be flat or noisy-but-stable rather than climbing. **Don't expect a clean horizontal line** — real memory readings always have noise. What you're looking for is the *trend* component disappearing. Variance of a few MB around a mean is normal and healthy. A consistent climb is the leak.

**Useful rule of thumb:** if peak-to-trough variance is under ~1% of total memory and the trend is flat, you're stable. If the trend has any slope at all over 5+ minutes, there's still something leaking.

In this lab there's only one leaker, so memory will plateau within seconds of the kill.

---

### Step 7: Write the incident report

A real incident isn't over when the bleeding stops. The next person on call needs to know what happened, why, and how to stop it from happening again. Write the report to `/tmp/incident-report.txt`:

```bash
cat > /tmp/incident-report.txt << 'EOF'
# Incident Report: Memory Leak on Application Server
# Ticket: INCIDENT-MON-002

## Summary
Server memory was growing linearly, projected to trigger OOM kill within
2 hours. Root cause was an in-process Python "cache" service that
accumulated entries indefinitely without eviction.

## Root Cause
A Python process was inserting ~10KB entries into an in-memory dictionary
roughly 5 times per second. The dictionary had no eviction policy
(no TTL, no max size, no LRU), so memory consumption grew without bound
at approximately 3 MB per minute.

## Diagnosis Path
1. Confirmed memory trend via /var/log/monitoring/memory.log
2. Ranked processes by memory using `ps aux --sort=-%mem`
3. Identified two python3 processes; one with growing RSS, one stable
4. Inspected command lines (visible directly in `ps` output for inline
   scripts) — confirmed cache-accumulation loop versus a benign sleep loop
5. Watched RSS over 60 seconds to confirm linear growth in one process
   while the other stayed flat
6. Killed the leaking process with SIGTERM
7. Verified legitimate application unaffected (ps showed it still alive)
8. Confirmed memory growth halted in monitoring log

## Resolution
- Sent SIGTERM to the leaking process
- Confirmed legitimate application unaffected (running, not zombie)
- Memory growth halted; readings flatlined within seconds

## Prevention
1. Add an eviction policy (LRU, TTL, or max-size) to any in-process cache
2. Replace the in-process cache with Redis or Memcached, which have
   eviction built in
3. Set per-container memory limits so a leak in one service can't
   exhaust the host
4. Add monitoring alerts on per-process memory growth rate, not just
   absolute usage — a growing process at 40% is a bigger risk than
   a stable one at 80%
5. Run containers with `--init` (or `init: true` in compose) so zombie
   children of killed processes are reaped properly
6. Code review checklist item: any dict/list that grows in a loop must
   have a documented bound
EOF
```

The validator will check that this file exists, has substantive content, mentions the leak using multiple relevant terms, and describes resolution or prevention. The report above hits all of those.

---

### Step 8: Run the validator

Exit the container (or run from outside the host's shell). Run:

```bash
lab validate 051
```

The validator checks:

| # | Check | What it confirms |
|---|---|---|
| 1 | Container is running | Sanity — nothing else matters if the lab box is down |
| 2 | Leaking process has been killed | Process state is dead OR zombie (both count — see Gotcha #3) |
| 3 | Legitimate application still running | State `R`, `S`, or `D` — alive and not zombified |
| 4 | No python3 process consuming excessive memory | RSS-based — catches "killed wrong one and started a replacement" |
| 5 | Incident report created | File exists at `/tmp/incident-report.txt` |
| 6 | Report has substantive content | ≥200 chars — stops single-word reports passing |
| 7 | Report identifies leak with multiple terms | ≥2 of: memory, leak, cache, growing, growth, unbounded, eviction, dictionary, RSS |
| 8 | Report describes resolution or prevention | Mentions kill/terminate/fix/prevent/eviction/limit/monitor etc. |

If all eight pass, you're done.

---

## How Would I Have Known Any of This Coming In Cold?

This is the bit that matters for interview prep. Walking through the reasoning explicitly:

**Q: I arrived with no information except "memory is climbing." How did I know to use `ps aux --sort=-%mem`?**

Because memory problems always decompose the same way: total system memory → per-process memory → per-process trend → root cause in the code. `ps` is the standard tool for the second step on any Linux box, anywhere. If you're ever unsure where to start with "X is high on a server," the answer is almost always *rank the processes by X*.

**Q: The system memory looked fine at first — why didn't I conclude the ticket was wrong?**

Because system-level metrics lag per-process metrics. A leak at 3 MB/min is invisible at the system level for the first hour but obvious at the process level immediately. Always zoom in before concluding a ticket is stale.

**Q: Why didn't I just `kill -9` the heaviest process immediately?**

Because the heaviest process at any given moment isn't necessarily the leaker — it might just be a legitimately memory-hungry application. The diagnostic signature of a leak is *unbounded growth*, not *high absolute usage*. Without the `watch` step (Step 3) confirming the growth, we'd be guessing.

**Q: Why kill (SIGTERM) instead of kill -9 (SIGKILL)?**

SIGTERM lets the process shut down cleanly — flush logs, close connections, write final state. SIGKILL is the kernel ripping it out instantly. Always start with the polite version; escalate only if the process ignores it.

**Q: Why did I check with `ps` instead of `kill -0` after the kill?**

Because `kill -0` lies in two ways: PID recycling can give you a false positive (a different process now has the same PID), and zombies can give you a false positive (the original process is dead but its entry is still in the process table). `ps` shows the actual state of the process, including the `<defunct>` marker for zombies. Source of truth.

**Q: How would I do this in real life with proper tooling?**

In a production environment with Prometheus and Grafana you'd skip Steps 1-3 entirely — the dashboards would already show you which process is growing. You'd use heap profiling tools (`tracemalloc` for Python, `pprof` for Go, heap dumps for Java) to identify the exact data structure leaking memory inside the process. The lab's tools (`ps`, `/proc`) are the fallback for when you're SSHed into a box with nothing else.

---

## Lab Environment vs Real Life

| Lab | Real production |
|---|---|
| Two python processes on a single container | Hundreds of processes across many hosts |
| PID files conveniently provided | No labels — figure it out from cmdline, ports, or service registry |
| Manually run `ps` and `watch` | Prometheus/Datadog/CloudWatch dashboards already plotting this |
| Kill the process by hand | The fix is a code change with eviction, deployed via CI/CD |
| Container PID 1 doesn't reap zombies | Production containers run with `tini`/`--init` so zombies are reaped |
| Single container, no blast radius | Container memory limits + Kubernetes evict the offender automatically |
| Incident report in a text file | PagerDuty postmortem + Jira ticket + RCA review meeting |

The diagnostic *thinking* is identical. The tooling around it scales up.

---

## Real-World Gotcha Log (Discovered During Lab Run)

These are the surprises encountered while actually running the lab. They're the kind of details you only learn by doing, and they're disproportionately useful in interviews:

1. **System-level metrics lag per-process metrics.** A slow leak can be invisible in `free -m` for an hour while being plainly obvious in `ps aux`. Always check per-process before concluding a ticket is stale.

2. **`ps aux` shows inline script code directly.** When a process was started with `python3 -c "..."`, the entire script is in the COMMAND column. You may not need `/proc/<PID>/cmdline` at all.

3. **PID recycling can fool `kill -0`.** Linux reuses PIDs aggressively, especially in low-process environments like containers. `kill -0 <PID>` returning success doesn't always mean your target is alive.

4. **Zombies look alive to PID-based checks.** A `<defunct>` process is dead but still in the process table. `kill -0` returns success for zombies. Use `ps` to see the real state.

5. **Container PID 1 often doesn't reap zombies.** Simple PID 1 commands like `tail -f /dev/null` aren't designed as init systems. Production fix: `docker run --init` or `init: true` in compose. For lab validation: check process *state*, not just existence.

6. **The diagnostic signature of a leak is the trend, not the value.** A 4 GB process is fine if it's been at 4 GB for a year. A 200 MB process growing from 50 MB in an hour is the problem.

---

## Key Concepts

- **RSS vs %MEM vs VSZ:** RSS is physical RAM the process actually has resident. %MEM is RSS as a percentage of total RAM. VSZ is virtual size — includes memory the process *could* use but hasn't actually touched. RSS is the one that matters for leaks.
- **A leak is a trend, not a value:** 4 GB used isn't a leak; 4 GB and climbing is.
- **`/proc` is the kernel's window:** Anything you want to know about a running process is in `/proc/<PID>/`. `cmdline`, `status`, `stat`, `fd`, `maps`, `environ` — all readable as files.
- **Process states (`R`/`S`/`D`/`Z`/`T`):** Found in `ps` output and in `/proc/<PID>/stat`. `Z` is the special one — dead but unreaped.
- **Caches without eviction are leaks:** This is one of the most common production bugs. "Just stick it in a dict for now" turns into a 3am page six months later.
- **Verify before destructive actions:** Confirm process identity (cmdline) and growth (watch) before `kill`. The two-second pause to verify is cheaper than the outage from killing the wrong thing.
- **Verify with the right tool:** `ps` for process state, not `kill -0`.

---

## Common Mistakes

- Killing the highest-memory process without confirming it's *growing*.
- Trusting the PID files without checking cmdline — in real life they're often wrong.
- Using `kill -9` first. Start with SIGTERM and escalate only if needed.
- Trusting `kill -0` to confirm a process is dead — it can return success for both PID-recycled processes and zombies.
- Restarting the whole container to "fix" memory. The leak comes back the moment the container starts again.
- Writing a report that says "killed the bad process" without identifying the *cause* (no eviction policy). The next on-call shift needs to know what to fix in the code, not just what was killed.
- Confusing high memory with leaking memory. A 2 GB process that's been at 2 GB for a year is fine. A 200 MB process that's grown from 50 MB in an hour is a problem.
- Concluding the ticket is wrong because `free -m` looks calm. Slow leaks don't show up at the system level for hours.

---

## Reset Instructions

To restart the lab from a clean state:

```bash
docker compose down
docker compose up -d
```

This restarts the container, which reruns `inject-faults.sh` and respawns both Python processes from scratch. PIDs will differ, but the leaker and legit app will be back in their starting positions.
