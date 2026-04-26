# Lab 051 — Memory Leak Detection

## TLDR (Plain English)

**What's wrong:** A server's memory usage keeps climbing and won't stop. Eventually the system will run out of RAM and the OOM killer will start terminating processes at random — possibly the wrong ones — causing an outage. Two Python processes are running on the box, and one of them is the culprit. The other is doing its job correctly and must not be touched.

**Why it's happening:** One of the Python processes is acting as a "cache" — but it's a cache that only ever adds entries and never removes them. Every fifth of a second it writes another 10KB blob into a dictionary in memory. The dictionary just grows forever. That's not really a cache, that's a memory leak with a misleading name.

**How we fix it:**
1. Watch memory usage to confirm the trend is actually upward (not a spike).
2. Rank processes by memory consumption to find the heaviest one.
3. Confirm *which* process is which — kill the wrong one and we cause a different outage.
4. Kill the leaker.
5. Verify the legitimate app survived.
6. Write the incident report so the next person on call understands what happened.

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

You'll see timestamped memory readings. The numbers should be climbing. If they're climbing, the ticket is accurate and we keep going.

**Why we did this first:** Real engineers don't trust tickets blindly. Confirming the symptom in 30 seconds saves you from an hour of investigating a non-issue.

---

### Step 2: Rank processes by memory consumption

Memory is climbing. Now we need to find *what's consuming it*. The standard tool for this:

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

**Why we ranked rather than guessed:** The ticket said memory is high but didn't say what's responsible. `top`-style ranking is the fastest way to narrow from "the whole system" to "this one process." It's the equivalent of triage in A&E — the patient bleeding the most gets seen first.

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

Let it run for 30-60 seconds. You should see the RSS column for one of the Python processes ticking upward visibly. The other process's RSS stays flat. That's the signature of a leak: **unbounded linear growth in one process's memory while others are stable**.

Press `Ctrl+C` to exit `watch`.

**Why we watched rather than relied on a single snapshot:** A snapshot can't distinguish "uses a lot" from "leaks a lot." Without the trend, we'd be guessing. The trend is the diagnosis.

---

### Step 4: Identify which process is which

We now have two Python PIDs and we know one is leaking. **We must not kill the wrong one.** Killing the legitimate app while leaving the leaker alive would be a worst-case outcome — the leak continues *and* we've caused a separate outage.

The lab kindly stores the PIDs in files for us:

```bash
cat /tmp/leaky.pid
cat /tmp/legit-app.pid
```

But in real life there are no helpful pid files telling you which is which. So let's pretend those files don't exist and do this the way you'd do it on an unfamiliar production box.

First, get the PIDs of the two python processes:

```bash
ps aux | grep python3 | grep -v grep
```

| Component | What it does |
|---|---|
| `ps aux` | All processes |
| `\| grep python3` | Filter to only lines containing "python3" |
| `\| grep -v grep` | Exclude the `grep python3` command itself from the results (`-v` means invert) |

Now you have two PIDs. To work out what each one is actually *doing*, look at its command line via `/proc`:

```bash
cat /proc/<PID>/cmdline | tr '\0' ' '; echo
```

Replace `<PID>` with each of the two PIDs in turn.

| Component | What it does |
|---|---|
| `/proc/<PID>/cmdline` | A virtual file the kernel exposes containing the exact command that started the process |
| `tr '\0' ' '` | The cmdline file separates arguments with null bytes (`\0`); translate them to spaces so it's readable |
| `; echo` | Add a newline at the end (cmdline doesn't end with one) so the prompt isn't on the same line |

When you read the output, you'll see the actual Python code each process is running. One of them contains a tight loop that builds a dictionary called `cache`, adding entries with a 10KB string value. That's the leaker — a "cache" that never evicts is a memory leak by another name. The other is a simple `while True: time.sleep(60)` — does nothing, uses constant memory, leave it alone.

**The reasoning chain at this step:**

1. We know memory is leaking (Step 1)
2. We know which process has the highest RSS (Step 2)
3. We know that process's RSS is growing while the other's is flat (Step 3)
4. We've now confirmed *what code is running* in each process (Step 4)
5. The growing process is running cache-accumulation code with no eviction → confirmed cause

Only now have we earned the right to kill it.

---

### Step 5: Kill the leaker

```bash
kill <PID-of-leaker>
```

`kill` sends SIGTERM by default, which asks the process to shut down cleanly. For a runaway Python loop this is enough; we don't need `kill -9` (SIGKILL) unless SIGTERM is ignored.

Verify it's dead:

```bash
kill -0 <PID-of-leaker>
```

| Component | What it does |
|---|---|
| `kill -0 <PID>` | Sends signal 0, which doesn't actually do anything to the process — but `kill` returns success if the process exists and failure if it doesn't. It's a "is this process alive?" probe |

If the command returns an error like "No such process," the leaker is dead. Good.

Now verify the legit app is **still alive**:

```bash
kill -0 <PID-of-legit-app>
```

This should return success silently (no output, exit code 0). If it errors, you killed the wrong thing and need to restart the container and try again.

**Why we verified both:** "I killed something" is not the same as "I killed the right thing and only the right thing." Two checks, two confirmations.

---

### Step 6: Confirm the bleed has stopped

Pull up `watch` again and check that memory has stabilised:

```bash
watch -n 2 'ps aux --sort=-%mem | head -5'
```

Or check the monitoring log:

```bash
tail -f /var/log/monitoring/memory.log
```

The numbers should now flatline rather than climb. If they're still climbing, there's a second leaker we missed — back to Step 2.

In this lab there's only one leaker, so memory will plateau.

---

### Step 7: Write the incident report

A real incident isn't over when the bleeding stops. The next person on call needs to know what happened, why, and how to stop it from happening again. Write the report to `/tmp/incident-report.txt`:

```bash
cat > /tmp/incident-report.txt << 'EOF'
# Incident Report: Memory Leak on Application Server
# Ticket: INCIDENT-MON-002

## Summary
Server memory was growing linearly over a 6-hour window, projected to
trigger OOM kill within 2 hours. Root cause was an in-process Python
"cache" service that accumulated entries indefinitely without eviction.

## Root Cause
A Python process was inserting ~10KB entries into an in-memory dictionary
roughly 5 times per second. The dictionary had no eviction policy
(no TTL, no max size, no LRU), so memory consumption grew without bound.

## Diagnosis Path
1. Confirmed upward memory trend via /var/log/monitoring/memory.log
2. Ranked processes by memory using `ps aux --sort=-%mem`
3. Identified two python3 processes; one with growing RSS, one stable
4. Read /proc/<PID>/cmdline for both to identify the cache-accumulation
   loop versus a benign sleep loop
5. Killed the leaking process, left the legitimate app running
6. Verified memory stabilised post-kill

## Resolution
- Sent SIGTERM to the leaking process
- Confirmed legitimate application unaffected
- Memory growth halted

## Prevention
1. Add an eviction policy (LRU, TTL, or max-size) to any in-process cache
2. Replace the in-process cache with Redis or Memcached, which have
   eviction built in
3. Set per-container memory limits so a leak in one service can't
   exhaust the host
4. Add monitoring alerts on per-process memory growth rate, not just
   absolute usage — a growing process at 40% is a bigger risk than
   a stable one at 80%
5. Code review checklist item: any dict/list that grows in a loop must
   have a documented bound
EOF
```

The validator will check that this file exists and that it mentions at least one of: memory, leak, cache, growing. The report above hits all four.

---

### Step 8: Run the validator

Exit the container (or run from outside) and execute the validation script. The validator will check:

- The leaking process is dead
- The legitimate app is still running
- The incident report exists
- The report mentions the leak

If all four pass, you're done.

---

## How Would I Have Known Any of This Coming In Cold?

This is the bit that matters for interview prep. Walking through the reasoning explicitly:

**Q: I arrived with no information except "memory is climbing." How did I know to use `ps aux --sort=-%mem`?**

Because memory problems always decompose the same way: total system memory → per-process memory → per-process trend → root cause in the code. `ps` is the standard tool for the second step on any Linux box, anywhere. If you're ever unsure where to start with "X is high on a server," the answer is almost always *rank the processes by X*.

**Q: How did I know to look at `/proc/<PID>/cmdline` rather than just trusting the PID files?**

Two reasons. First, real production servers don't leave PID files lying around labelling the leaker for you. Second, even when PID files exist, they can be stale or wrong — a process can crash and restart with a different PID without the file being updated. `/proc/<PID>/cmdline` is sourced from the kernel itself, so it's always current.

**Q: Why didn't I just `kill -9` the heaviest process immediately?**

Because the heaviest process at any given moment isn't necessarily the leaker — it might just be a legitimately memory-hungry application. The diagnostic signature of a leak is *unbounded growth*, not *high absolute usage*. Without the `watch` step (Step 3) confirming the growth, we'd be guessing.

**Q: Why kill (SIGTERM) instead of kill -9 (SIGKILL)?**

SIGTERM lets the process shut down cleanly — flush logs, close connections, write final state. SIGKILL is the kernel ripping it out instantly. Always start with the polite version; escalate only if the process ignores it.

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
| Single container, no blast radius | Container memory limits + Kubernetes evict the offender automatically |
| Incident report in a text file | PagerDuty postmortem + Jira ticket + RCA review meeting |

The diagnostic *thinking* is identical. The tooling around it scales up.

---

## Key Concepts

- **RSS vs %MEM vs VSZ:** RSS is physical RAM the process actually has resident. %MEM is RSS as a percentage of total RAM. VSZ is virtual size — includes memory the process *could* use but hasn't actually touched. RSS is the one that matters for leaks.
- **A leak is a trend, not a value:** 4GB used isn't a leak; 4GB and climbing is.
- **`/proc` is the kernel's window:** Anything you want to know about a running process is in `/proc/<PID>/`. `cmdline`, `status`, `fd`, `maps`, `environ` — all readable as files.
- **Caches without eviction are leaks:** This is one of the most common production bugs. "Just stick it in a dict for now" turns into a 3am page six months later.
- **Verify before destructive actions:** `kill -0` to confirm process identity before `kill`. The two-second pause to verify is cheaper than the outage from killing the wrong thing.

---

## Common Mistakes

- Killing the highest-memory process without confirming it's growing.
- Trusting the PID files without checking cmdline — in real life they're often wrong.
- Using `kill -9` first. Start with SIGTERM and escalate only if needed.
- Restarting the whole container to "fix" memory. The leak comes back the moment the container starts again.
- Writing a report that says "killed the bad process" without identifying the *cause* (no eviction policy). The next on-call shift needs to know what to fix in the code, not just what was killed.
- Confusing high memory with leaking memory. A 2GB process that's been at 2GB for a year is fine. A 200MB process that's grown from 50MB in an hour is a problem.
