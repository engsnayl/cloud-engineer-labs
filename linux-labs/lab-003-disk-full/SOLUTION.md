# Solution Walkthrough — Disk Full

## The Problem

The disk is nearly full, which can cause applications to crash, databases to corrupt, and the system to become unresponsive. There are **four sources** of wasted disk space:

1. **Massive application log files** — the app in `/var/log/myapp/` has accumulated ~150MB of log files (`application.log`, `application.log.1`, `application.log.2`) because nobody set up log rotation.
2. **Old temporary files** — 20 stale `.tmp` files in `/tmp/reports/` that were never cleaned up (~60MB total).
3. **Core dump files** — two large core dumps in `/var/cache/myapp/` (~50MB total) from past crashes that nobody investigated or removed.
4. **A deleted file still held open by a running process** — this is the sneaky one. A 20MB file was deleted with `rm`, but the process that had it open still holds a file descriptor to it. The space won't actually be freed until that process releases the file or is killed. This is a classic gotcha that trips up even experienced engineers.

There's also a prevention requirement: you need to set up `logrotate` so the log files don't grow out of control again.

## Thought Process

When a disk is full, an experienced engineer works top-down:

1. **How bad is it?** Run `df -h` to see overall disk usage percentages.
2. **Where is the space being used?** Use `du -sh /*` to find which top-level directories are biggest, then drill down.
3. **Find the biggest files** using `find / -type f -size +10M` to locate anything unusually large.
4. **Check for hidden space consumption** — deleted files held open by processes won't show up in normal `du` output. Check `/proc/*/fd` or use `lsof +L1` to find them.
5. **Clean up and prevent recurrence** — don't just delete files; set up logrotate so it doesn't happen again.

## Step-by-Step Solution

### Step 1: Assess the damage

```bash
df -h /
```

**What this does:** Shows disk usage in human-readable format (`-h` means sizes like "150M" instead of raw bytes). The `/` argument checks the root filesystem. Look at the "Use%" column — it'll be very high.

### Step 2: Find the biggest space consumers

```bash
du -sh /var/log/myapp/* /tmp/reports/* /var/cache/myapp/*
```

**What this does:** `du` stands for "disk usage." The `-s` flag gives a summary (total per directory/file rather than every subdirectory), and `-h` makes it human-readable. This reveals the large log files, temp files, and core dumps.

### Step 3: Clean up the oversized application logs

```bash
rm /var/log/myapp/application.log.1 /var/log/myapp/application.log.2
> /var/log/myapp/application.log
```

**What this does:** First, we remove the old rotated log files entirely. Then, for the current `application.log`, we use the `>` redirect to truncate it to zero bytes *without deleting the file*. This is important — if a process is currently writing to this file, deleting and recreating it would cause the process to lose its file handle. Truncating it keeps the file handle valid while reclaiming the space.

### Step 4: Clean up the old temp files

```bash
rm -f /tmp/reports/*.tmp
```

**What this does:** Removes all files ending in `.tmp` from the reports directory. The `-f` flag means "force" — don't ask for confirmation and don't error if a file doesn't exist.

### Step 5: Remove the core dumps

```bash
rm -f /var/cache/myapp/core.dump.*
```

**What this does:** Removes the accumulated core dump files. Core dumps are snapshots of a program's memory at the moment it crashed — useful for debugging, but they're large and shouldn't pile up.

### Step 6: Find and deal with the deleted-but-held-open file

```bash
ls -la /proc/*/fd 2>/dev/null | grep deleted
```

**What this does:** Looks through the file descriptors of every running process for any that point to deleted files. When you `rm` a file that a process still has open, Linux marks it as "(deleted)" but the disk space isn't freed. You'll find a process that's still holding onto the deleted `debug-old.log` file.

### Step 7: Kill the process holding the deleted file

```bash
# Find the PID of the process holding the file
ps aux | grep fake-app
# Kill it (replace <PID> with the actual process ID)
kill <PID>
```

**What this does:** First, we identify the process that's holding the deleted file open. Then we send it a graceful termination signal with `kill`. Once the process exits, it releases the file descriptor and the disk space is finally freed. The default `kill` signal is `SIGTERM`, which asks the process to shut down cleanly.

### Step 8: Set up logrotate to prevent recurrence

```bash
cat > /etc/logrotate.d/myapp << 'EOF'
/var/log/myapp/*.log {
    daily
    rotate 3
    size 10M
    compress
    missingok
    notifempty
    copytruncate
}
EOF
```

**What this does:** Creates a logrotate configuration file that will automatically manage the application's log files. Here's what each directive means:
- `daily` — check the logs once a day
- `rotate 3` — keep only 3 old copies of each log file
- `size 10M` — only rotate if the file exceeds 10MB
- `compress` — compress old log files with gzip to save space
- `missingok` — don't error if the log file doesn't exist
- `notifempty` — don't rotate empty files
- `copytruncate` — copy the current log, then truncate the original (safe for apps that keep the log file open)

### Step 9: Verify disk usage is healthy

```bash
df -h /
```

**What this does:** Check that disk usage has dropped below 70%. If it hasn't, look for other large files you may have missed.

## Docker Lab vs Real Life

- **Finding held-open files:** In this lab we manually searched `/proc/*/fd`. On a real server with `lsof` installed, you'd use `lsof +L1` which is much easier — it lists all files that have been "unlinked" (deleted) but are still open.
- **Logrotate timing:** In this lab, logrotate won't actually run automatically because Docker containers don't have cron or systemd timers by default. On a real server, logrotate is typically triggered daily by a cron job or systemd timer that's already set up.
- **Disk monitoring:** In production, you'd have monitoring (like CloudWatch, Prometheus, or Datadog) that alerts you when disk usage exceeds a threshold (commonly 80%), so you'd catch this before it becomes an emergency.
- **Core dumps:** On production servers, you'd configure core dump limits with `ulimit -c` or in `/etc/security/limits.conf` to prevent them from filling the disk.

## Key Concepts Learned

- **`df -h` for the big picture, `du -sh` for drilling down** — these are the two essential commands for diagnosing disk space issues
- **Deleted files aren't always gone** — if a process has a file open when you delete it, the space isn't freed until the process releases the file descriptor
- **Truncate vs. delete** — when a process is writing to a log file, truncate it with `> filename` rather than deleting and recreating it
- **Logrotate prevents recurrence** — finding and deleting big files is a bandaid; setting up automated log rotation is the real fix
- **Check `/proc/*/fd` for phantom space usage** — when `df` shows more used space than `du` accounts for, deleted-but-held-open files are usually the culprit

## Common Mistakes

- **Only cleaning up the obvious files** — many people delete the big log files and temp files, then wonder why disk usage is still high. The deleted-but-held-open file is the one most people miss.
- **Deleting the active log file with `rm` instead of truncating** — if the application has the file open, `rm` won't free the space (same held-open problem), and the application may stop logging entirely because its file handle is now invalid
- **Forgetting to set up logrotate** — cleaning up disk space without preventing recurrence means you'll be doing this again next week
- **Using `kill -9` when `kill` would do** — `kill -9` (SIGKILL) is a last resort. Always try `kill` (SIGTERM) first, which lets the process clean up after itself
- **Not checking for multiple sources of bloat** — disk space problems often come from several places at once, not just one big file
