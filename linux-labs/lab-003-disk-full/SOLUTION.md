# Solution — Lab 003: Disk Full

## TLDR
The /data disk is full. Run df -h to see it, then go find what's eating all the space with du -sh /data/*. There's old logs, backups, and temp files that can be safely deleted. Clear enough space so the disk isn't at 100% and the service can write again.

## The Problem

The server's data partition (`/data`) is full. An application that generates reports can't write files because there's no free space. Something — or several things — have consumed the available disk space and need to be cleaned up.

## Thought Process

When a disk is full, the investigation always follows the same pattern:

1. **Confirm it** — use `df` to verify the disk is actually full
2. **Find where** — use `du` to drill down directory by directory
3. **Find what** — use `find` to locate the biggest individual files
4. **Decide what's safe** — check file ages and types before deleting
5. **Clean up** — remove what's safe, verify space is freed

This is the process you'd follow every time, whether it's a Docker lab or a production server at 3am.

## Step-by-Step Solution

### Step 1: Confirm the disk is full

```bash
df -h
```

**What this does:** `df` stands for "disk free". The `-h` flag means "human readable" — it shows sizes in MB/GB instead of raw bytes. You're looking for a filesystem that's at 90%+ usage.

You'll see the `/data` partition is over 90% full. This confirms the problem is real and tells you which filesystem is affected and roughly how much space needs to be freed.

### Step 2: Find which directories are using the most space

```bash
du -sh /data/* 2>/dev/null | sort -h
```

**What this does:** `du` stands for "disk usage". `-s` means "summary" (total per directory, not every sub-file). `-h` means human readable. The `sort -h` sorts by size so the biggest directories appear at the bottom. The `2>/dev/null` hides "permission denied" errors that would clutter the output.

You'll see that `/data/backups`, `/data/logs`, and `/data/tmp` are the main consumers. These are your investigation targets.

### Step 3: Investigate /data/logs

```bash
ls -lh /data/logs/
```

**What you'll find:**
- `application.log` — a single file around 10MB. This is a log file that's been growing without any rotation or size limit.
- `debug.log.1` through `debug.log.5` — five old rotated debug logs at ~7MB each. These are leftovers that should have been cleaned up by logrotate but weren't configured.

**What's safe to delete:** All of these. Application logs can always be recreated — the app will just start a new log file. Old rotated logs (the `.1`, `.2` etc.) are historical and serve no active purpose.

```bash
rm /data/logs/application.log
rm /data/logs/debug.log.*
```

**Why this is safe:** Log files record what already happened. Deleting them doesn't break the application — it just means you lose the historical record. In production you might archive them first, but in an emergency you delete them.

### Step 4: Investigate /data/backups

```bash
ls -lh /data/backups/
```

**What you'll find:** Seven database backup archives (`db-backup-2025-01-XX.tar.gz`), each around 11MB. These are old daily backups that accumulated because nobody configured a retention policy.

**What's safe to delete:** All the old ones. You might want to keep the most recent backup as a safety net, but the older ones are redundant — each backup is a full snapshot, so you only need the latest.

```bash
# Keep the newest, delete the rest
cd /data/backups
ls -t *.tar.gz | tail -n +2 | xargs rm
```

**What that command does:** `ls -t` lists files sorted by modification time (newest first). `tail -n +2` skips the first line (the newest file) and outputs the rest. `xargs rm` deletes each of those files. The net result: keep the newest backup, delete all the others.

Or if you prefer something simpler and more explicit:

```bash
# Delete them all — in an emergency this is fine
rm /data/backups/db-backup-2025-01-01.tar.gz
rm /data/backups/db-backup-2025-01-04.tar.gz
rm /data/backups/db-backup-2025-01-07.tar.gz
rm /data/backups/db-backup-2025-01-10.tar.gz
rm /data/backups/db-backup-2025-01-13.tar.gz
rm /data/backups/db-backup-2025-01-16.tar.gz
# Keep db-backup-2025-01-19.tar.gz as the latest
```

### Step 5: Investigate /data/tmp

```bash
ls -lh /data/tmp/
```

**What you'll find:** Twenty `.tmp` files, each around 2MB. These are temporary files created by the reporting application during report generation. When the app crashed, it left these behind.

**What's safe to delete:** Everything in a tmp directory is temporary by definition. These are stale leftovers from crashed processes.

```bash
rm /data/tmp/*.tmp
```

### Step 6: Verify you freed enough space

```bash
df -h
```

You should now see the `/data` partition has significantly more free space — well over the 50MB the application needs to function.

### Step 7: Verify the application data is intact

```bash
ls -la /data/myapp/
ls -la /data/myapp/data/
```

**Critical check:** Make sure you did NOT delete anything from `/data/myapp/`. This directory contains:
- `config.json` — the application configuration
- `data/reports.db` — the application database
- `status.txt` — a health check file

These are live application data. Deleting these would break the application worse than the disk being full.

## Docker Lab vs Real Life

| In this lab | In production |
|---|---|
| `rm /data/logs/*.log` | Configure logrotate to automatically manage log sizes |
| `rm /data/backups/old-*.tar.gz` | Set up a backup retention policy (e.g. keep 7 days) |
| `rm /data/tmp/*.tmp` | Configure the app to clean up temp files, or use systemd-tmpfiles |
| Files are created by inject-faults.sh | Files accumulate over days/weeks/months of normal operation |

## Key Concepts Learned

- **`df -h`** shows you how full each filesystem is — always your first command for disk issues
- **`du -sh <dir>/*`** lets you drill down directory by directory to find where space is being used
- **`find /data -type f -size +1M`** finds individual large files on the affected partition
- **Logs, backups, and temp files** are the three most common causes of disk full in production
- **Application data** (databases, configs) should never be deleted to free space
- **Prevention > cure** — logrotate and backup retention policies stop this from happening

## Common Mistakes

- **Deleting application data** instead of logs/backups — always check what a file IS before removing it
- **Only fixing one thing** — disk full is often caused by multiple culprits, not just one
- **Forgetting to check /data/tmp** — temporary files are easy to overlook but can accumulate fast
- **Not verifying afterwards** — always run `df -h` after cleanup to confirm you freed enough space
