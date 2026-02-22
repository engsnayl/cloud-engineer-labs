# Solution Walkthrough — Swap and Memory Pressure

## The Problem

The system is under memory pressure from a leaking process, and it has no safety net because swap is disabled. There are **two issues**:

1. **A memory-leaking process is running** — a Python script is continuously appending data to a list, growing by 100KB every half second. It will never stop or free this memory on its own. Left unchecked, it will eventually consume all available RAM, triggering the OOM (Out of Memory) killer, which could terminate critical services.
2. **Swap is not enabled** — a swap file exists at `/swapfile` (256MB, already formatted with `mkswap`), but it was never activated with `swapon`. Without swap, the system has zero buffer when physical RAM runs out. The OOM killer gets triggered much sooner because there's no overflow space.

There's also a **legitimate Python application** (`python3 /opt/app.py`) that must be kept running. The challenge is to kill the memory-leaking process without harming the legitimate one, and then enable swap as a safety net.

## Thought Process

When a system is running low on memory, an experienced engineer takes a systematic approach:

1. **Assess the damage** — `free -h` shows total, used, and available memory, plus swap status. If swap shows all zeros, it's not enabled.
2. **Find the memory hog** — `ps aux --sort=-%mem | head` shows processes sorted by memory usage. The biggest consumer is your likely culprit.
3. **Be surgical** — identify the exact PID of the leaking process and kill it without touching the legitimate application.
4. **Enable swap** — if a swap file exists but isn't active, enable it to prevent this situation from being as dangerous next time.

The key insight is that swap isn't a performance feature — it's a safety net. When physical RAM runs out, swap gives the system somewhere to put less-used memory pages instead of killing processes. It's slower than RAM, but crashing is slower than slow.

## Step-by-Step Solution

### Step 1: Check memory and swap status

```bash
free -h
```

**What this does:** Shows memory and swap usage in human-readable format. You'll see:
- **Mem line**: Shows total physical RAM, how much is used, and how much is available
- **Swap line**: All zeros — swap is not enabled at all

The `-h` flag makes the output human-readable (e.g., "256M" instead of "262144").

### Step 2: Find the memory-eating process

```bash
ps aux --sort=-%mem | head -10
```

**What this does:** Lists all processes sorted by memory usage (highest first) and shows the top 10. The `--sort=-%mem` flag sorts by memory percentage in descending order. You'll see a Python process consuming a large and growing amount of memory. Look at the command column — the leaking process runs an inline script with `data.append`, while the legitimate app runs `/opt/app.py`.

### Step 3: Identify the exact PIDs

```bash
pgrep -a -f "data.append"
pgrep -a -f "python3 /opt/app.py"
```

**What this does:** Finds the PIDs of both Python processes by matching their command lines. The `-a` flag shows the full command, and `-f` matches against the full command line. This lets you clearly distinguish the leaking process from the legitimate one.

### Step 4: Kill the memory-leaking process

```bash
pkill -f "data.append"
```

**What this does:** Sends a SIGTERM signal to the process whose command line contains "data.append." This terminates the memory-leaking Python script. We use `-f` to match the full command line because both processes are `python3` — we need to target the specific one with the leak. The memory used by this process will be freed immediately when it exits.

### Step 5: Verify the leak is stopped and the legitimate app survives

```bash
pgrep -a -f "data.append"
pgrep -a -f "python3 /opt/app.py"
```

**What this does:** Confirms that the leaking process is gone (no output from the first command) and the legitimate app is still running (PID shown by the second command).

### Step 6: Check that the swap file exists and is formatted

```bash
file /swapfile
ls -lh /swapfile
```

**What this does:** `file /swapfile` tells you what type of file it is — you should see "Linux swap file." `ls -lh` shows the file size (256MB) and permissions (should be `600`). The swap file is ready to use; it just needs to be activated.

### Step 7: Enable swap

```bash
swapon /swapfile
```

**What this does:** Activates the swap file, making it available for the system to use as overflow memory. After this, when physical RAM fills up, the kernel can move less-used memory pages to this swap file instead of killing processes.

### Step 8: Verify swap is active

```bash
free -h
```

**What this does:** Shows memory and swap status again. This time, the Swap line should show a non-zero total (256MB). This confirms swap is active and providing a memory safety net.

### Step 9: Verify overall system health

```bash
free -h | grep Mem | awk '{printf "Memory usage: %.0f%%\n", $3/$2 * 100}'
```

**What this does:** Calculates and displays the current memory usage as a percentage. After killing the leaking process, memory usage should be well below 80%.

## Docker Lab vs Real Life

- **Swap in containers:** Docker containers typically share swap with the host system. In this lab, we're simulating a standalone server scenario. On a real server, swap is configured at the OS level, not per-container.
- **Swap persistence:** In this lab, `swapon /swapfile` enables swap only until the next reboot. On a real server, you'd also add an fstab entry: `/swapfile none swap sw 0 0` to make it persistent across reboots.
- **Swap size guidelines:** The traditional rule was "2x RAM for swap," but modern guidance varies. For servers with lots of RAM (16GB+), 1x RAM or even less is common. For database servers, some admins disable swap entirely to prevent performance degradation (preferring a crash over slow performance). AWS recommends swap for small instances.
- **OOM killer:** On a real Linux server, when memory runs out completely, the kernel's OOM (Out of Memory) killer picks a process to terminate based on a scoring system. It tries to kill the process using the most memory, but it can sometimes kill critical services instead. This is why swap matters — it delays the OOM killer, giving you time to react.
- **Memory monitoring:** In production, you'd have monitoring (Prometheus, Datadog, CloudWatch) that alerts when memory usage exceeds a threshold (typically 80-90%), so you'd catch a memory leak before it causes an OOM event.

## Key Concepts Learned

- **`free -h` is the go-to command for memory status** — it shows physical RAM usage and swap status at a glance
- **Swap is a safety net, not a performance feature** — it prevents the OOM killer from terminating processes when RAM fills up, at the cost of slower memory access
- **Memory leaks grow over time** — a process that allocates memory without ever freeing it will eventually consume all available RAM. The only fix is to kill the process (or fix the bug in the code).
- **`ps aux --sort=-%mem` finds memory hogs** — similar to `--sort=-%cpu` for CPU problems, this sorts by memory usage
- **Be precise when killing processes** — use command-line patterns (`pkill -f "data.append"`) to target the exact process without affecting similar ones

## Common Mistakes

- **Killing the wrong Python process** — both processes are `python3`, so you can't just use `killall python3`. You need to match the specific command line to distinguish the leaker from the legitimate app.
- **Enabling swap but not killing the leaking process** — swap buys you time, but it doesn't fix the leak. The process will eventually consume all swap space too. You need to stop the leak.
- **Not checking if the swap file exists before creating one** — in this lab, the swap file is already created and formatted. Running `mkswap` on it again would work, but on a real server you might accidentally overwrite an active swap file.
- **Setting wrong permissions on the swap file** — a swap file should have `600` permissions (only root can read/write). If other users can read the swap file, they could potentially extract sensitive data from other processes' memory.
- **Forgetting to add swap to fstab** — `swapon` only enables swap for the current session. Without an fstab entry, swap won't be activated after a reboot, leaving you vulnerable again.
