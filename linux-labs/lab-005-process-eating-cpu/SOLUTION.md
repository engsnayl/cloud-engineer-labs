# Solution Walkthrough — Process Eating CPU

## The Problem

A rogue process is consuming all the CPU on the server, making everything slow and unresponsive. The tricky part is that **the process is disguised** — it's been renamed to `analytics-worker` to look like a legitimate service, but it's actually `stress-ng`, a benchmarking tool that deliberately maxes out CPU usage.

Meanwhile, there's a **legitimate Python application** (`python3 /opt/app.py`) that must keep running. The challenge is to kill the rogue process without accidentally taking down the real application.

Here's what happened:
1. Someone copied the `stress-ng` binary to `/usr/local/bin/analytics-worker` (renaming it to look innocent)
2. They launched it with `--cpu 2 --timeout 0`, which means "spin up 2 CPU-eating workers that run forever"
3. The legitimate Python app is running normally and should be left alone

## Thought Process

When a server is slow and you suspect a runaway process, an experienced engineer follows this sequence:

1. **Identify the hog** — use `top` or `ps aux --sort=-%cpu` to see what's consuming the most CPU. Don't trust process names blindly — they can be changed.
2. **Investigate the suspicious process** — check where the binary lives, what it really is (using `file` command), and what arguments it was started with.
3. **Be surgical** — identify the exact PID(s) to kill. Don't use `killall` or `pkill` carelessly, because you might take out legitimate services.
4. **Verify** — after killing the rogue process, confirm that CPU usage dropped AND that the legitimate application is still running.

## Step-by-Step Solution

### Step 1: Identify what's eating CPU

```bash
ps aux --sort=-%cpu | head -10
```

**What this does:** Lists all running processes, sorted by CPU usage (highest first), and shows the top 10. The `--sort=-%cpu` flag sorts by CPU percentage in descending order (the `-` means descending). The `head -10` limits output to the top 10 lines. You'll see `analytics-worker` at the top, consuming a large percentage of CPU.

### Step 2: Investigate the suspicious process

```bash
file /usr/local/bin/analytics-worker
```

**What this does:** The `file` command examines a file and tells you what type it is. Instead of seeing a custom application, you'll see that `analytics-worker` is actually a standard ELF binary — and if you compare it with `stress-ng`, you'll find they're the same file. This confirms it's not a real analytics worker at all.

### Step 3: Get the exact PIDs of the rogue process

```bash
pgrep -a analytics-worker
```

**What this does:** `pgrep` finds processes by name, and the `-a` flag shows the full command line for each match. This gives you the exact PIDs you need to kill, and shows the command-line arguments (you'll see `--cpu 2 --timeout 0`, which confirms this is stress-ng doing intentional CPU burning).

### Step 4: Verify the legitimate app is running (so we know what to protect)

```bash
pgrep -a -f "python3 /opt/app.py"
```

**What this does:** Finds the legitimate Python application. The `-f` flag matches against the full command line, not just the process name. Note the PID — this is the process we need to keep alive.

### Step 5: Kill the rogue process

```bash
pkill -f analytics-worker
```

**What this does:** Sends a `SIGTERM` (graceful termination signal) to all processes matching "analytics-worker." The `-f` flag matches against the full command line. This will kill the main `analytics-worker` process and its CPU-burning child workers. We use `pkill` here because we want to match all related processes (the parent and its worker children).

### Step 6: Verify the rogue process is gone

```bash
pgrep -a analytics-worker
```

**What this does:** Checks that no `analytics-worker` processes are still running. This should return nothing (no output, no matches).

### Step 7: Verify the legitimate app is still running

```bash
pgrep -a -f "python3 /opt/app.py"
```

**What this does:** Confirms that the Python application survived our cleanup. It should still be running with the same PID as before.

### Step 8: Clean up the disguised binary

```bash
rm /usr/local/bin/analytics-worker
```

**What this does:** Removes the renamed `stress-ng` binary from `/usr/local/bin/` so it can't be accidentally (or maliciously) started again. This is a good practice — don't leave suspicious binaries lying around.

### Step 9: Verify system health

```bash
ps aux --sort=-%cpu | head -5
cat /proc/loadavg
```

**What this does:** The first command confirms no process is consuming excessive CPU. The second command shows the system load average — the three numbers represent the 1-minute, 5-minute, and 15-minute averages. The 1-minute average should be dropping toward a low value. A load average below 2.0 on a 2-CPU system means the system is healthy.

## Docker Lab vs Real Life

- **Process investigation:** On a real server, you'd also use `lsof -p <PID>` to see what files and network connections a suspicious process has open. Tools like `strace` can show you what system calls it's making in real time.
- **Checking binary identity:** In production, you might use `md5sum` or `sha256sum` to compare a suspicious binary against known binaries, or check if it matches packages installed by your package manager with `dpkg -S /path/to/binary` (Debian/Ubuntu) or `rpm -qf /path/to/binary` (Red Hat/CentOS).
- **Process monitoring:** In production, you'd have monitoring tools (Prometheus + Grafana, Datadog, CloudWatch) that alert you when CPU usage spikes, so you'd catch this much sooner.
- **System load:** In this lab we check `/proc/loadavg` directly. On a production server, you'd use `uptime` or `top` for a more user-friendly view, and your monitoring stack would track this over time.

## Key Concepts Learned

- **Process names can be misleading** — a process named `analytics-worker` might actually be something completely different. Always investigate suspicious processes using `file`, `ls -la`, and full command-line inspection.
- **`top` and `ps aux --sort=-%cpu` are your first tools** for diagnosing CPU problems
- **Be surgical when killing processes** — use specific PIDs or targeted `pkill` patterns rather than broad `killall` commands that might take out legitimate services
- **The `file` command reveals a binary's true identity** — it examines the file contents, not the filename
- **Load average** is a key system health metric — it represents the average number of processes waiting for CPU time. A load average below the number of CPU cores means the system is keeping up.

## Common Mistakes

- **Killing everything with `killall` or `kill -9 -1`** — this would take out the legitimate Python app along with the rogue process. Always identify the specific process to kill.
- **Trusting the process name** — just because something is called `analytics-worker` doesn't mean it's your analytics worker. Investigate first.
- **Using `kill -9` as a first resort** — always try `kill` (SIGTERM) first, which lets the process clean up. Only escalate to `kill -9` (SIGKILL) if the process doesn't respond to SIGTERM.
- **Forgetting to clean up the binary** — if you kill the process but leave `/usr/local/bin/analytics-worker` in place, it could be started again.
- **Not verifying the legitimate app survived** — always confirm that the services you want to keep are still running after your cleanup.
