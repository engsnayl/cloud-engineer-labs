# Solution Walkthrough — Cron Not Running

## The Problem

A scheduled backup job isn't running. There are **three separate issues** preventing it from working:

1. **The cron daemon isn't running** — cron is the service responsible for executing scheduled tasks on Linux. If the daemon itself isn't running, no scheduled jobs will execute, period. In Docker containers, services like cron don't auto-start the way they do on a normal server.
2. **The crontab entry has invalid syntax** — the backup job's schedule line has 6 time fields instead of the required 5. A cron schedule must have exactly 5 fields (minute, hour, day-of-month, month, day-of-week) followed by the command. The extra field makes cron misinterpret the entry, treating part of the schedule as the command.
3. **The backup script isn't executable** — the script at `/opt/scripts/backup.sh` has permissions `644` (read/write for owner, read for others) but no execute permission. Even if cron tried to run it, the system would refuse because the file isn't marked as executable.

## Thought Process

When a cron job isn't working, an experienced engineer checks things in this order:

1. **Is cron even running?** This is step zero. If the cron daemon isn't running, nothing else matters. Check with `pgrep cron` or `service cron status`.
2. **Is the crontab entry valid?** Run `crontab -l` and carefully count the fields. A cron entry has exactly 5 time fields before the command. This is the most common cron mistake — getting the syntax wrong.
3. **Can the script actually run?** Check that the script has execute permission, that its shebang line (`#!/bin/bash`) is correct, and that it runs successfully when triggered manually.
4. **Test manually** — run the script by hand to make sure it works independently of cron.

## Step-by-Step Solution

### Step 1: Check if the cron daemon is running

```bash
pgrep cron
```

**What this does:** Searches for running processes with "cron" in the name and prints their PIDs. If nothing is returned, cron isn't running. No cron daemon = no scheduled jobs, regardless of what's in the crontab.

### Step 2: Start the cron daemon

```bash
service cron start
```

**What this does:** Starts the cron service. The cron daemon runs in the background, waking up every minute to check if any scheduled jobs need to be executed.

### Step 3: Verify cron is now running

```bash
pgrep cron
```

**What this does:** Confirms that the cron daemon started successfully. You should now see a PID returned.

### Step 4: Check the current crontab

```bash
crontab -l
```

**What this does:** Lists the current user's crontab (scheduled tasks). The `-l` flag means "list." You'll see the backup entry, but if you count the fields carefully, you'll notice there are 6 time fields instead of 5:

```
0 2 * * * 0 /opt/scripts/backup.sh
```

The problem is `0 2 * * * 0` — that's 6 fields. Cron expects 5 time fields (`0 2 * * 0`) followed by the command. With 6 fields, cron thinks the command starts at `0` and `/opt/scripts/backup.sh` is an argument, so the job will fail or be misinterpreted.

### Step 5: Fix the crontab entry

```bash
crontab -l | sed 's|0 2 \* \* \* 0 /opt/scripts/backup.sh|0 2 * * 0 /opt/scripts/backup.sh|' | crontab -
```

Or, more simply, write a fresh crontab:

```bash
echo "0 2 * * 0 /opt/scripts/backup.sh" | crontab -
```

**What this does:** Replaces the crontab with a corrected entry. The fixed schedule `0 2 * * 0` means:
- `0` — at minute 0 (the top of the hour)
- `2` — at hour 2 (2:00 AM)
- `*` — any day of the month
- `*` — any month
- `0` — on Sunday (0 = Sunday, 1 = Monday, etc.)

So this runs the backup every Sunday at 2:00 AM. The `| crontab -` at the end pipes the corrected entry into the crontab (the `-` means "read from standard input").

### Step 6: Verify the fixed crontab

```bash
crontab -l
```

**What this does:** Confirms the crontab now has the correct 5-field syntax.

### Step 7: Make the backup script executable

```bash
chmod +x /opt/scripts/backup.sh
```

**What this does:** Adds execute permission to the backup script. The `+x` means "add execute permission." Without this, the system will refuse to run the script, returning a "Permission denied" error — even if cron tries to execute it.

### Step 8: Test the backup script manually

```bash
/opt/scripts/backup.sh
```

**What this does:** Runs the backup script directly to verify it works. This is always a good practice — test the script by hand before relying on cron to run it. If it fails here, it will definitely fail when cron runs it.

### Step 9: Verify the backup output was created

```bash
cat /var/backups/db-backup.sql
```

**What this does:** Shows the contents of the backup file that the script creates. You should see a timestamped backup header and a "completed successfully" message. This confirms the script works end-to-end.

## Docker Lab vs Real Life

- **Starting cron:** In this lab we use `service cron start` because Docker containers typically don't run systemd. On a production Ubuntu server, you'd use `systemctl start cron` and `systemctl enable cron` (the `enable` ensures cron starts automatically on boot).
- **Cron daemon auto-start:** On a real Linux server, cron is almost always running by default — it's started at boot by systemd. In Docker, no services auto-start because containers don't run an init system (unless you specifically configure one).
- **Cron logging:** On a real server, cron logs to `/var/log/syslog` (Debian/Ubuntu) or `/var/log/cron` (Red Hat/CentOS). When debugging cron issues in production, these logs are invaluable — they show you exactly when cron tried to run a job and what happened.
- **Backup strategy:** In production, a real backup script would dump an actual database (e.g., `mysqldump` or `pg_dump`), compress the output, and upload it to remote storage (like S3). You'd also want monitoring to alert you if a backup fails.

## Key Concepts Learned

- **Cron has 5 time fields, not 6** — the format is `minute hour day-of-month month day-of-week command`. Using 6 fields is one of the most common cron mistakes.
- **The cron daemon must be running** for any cron jobs to execute — this is easy to forget, especially in containers or minimal server setups.
- **Scripts need execute permission** — even if the content is correct, the file must have `+x` permission to be run as a script.
- **Always test cron scripts manually first** — run the script by hand before expecting cron to run it. This catches path issues, permission problems, and logic errors.
- **Cron jobs run with a minimal environment** — the `PATH` and other environment variables in a cron job are different from your interactive shell, which can cause scripts that work interactively to fail under cron.

## Common Mistakes

- **Miscounting cron fields** — the 5-field vs 6-field mistake is incredibly common. A helpful mnemonic: `M H DoM M DoW command` (Minute, Hour, Day of Month, Month, Day of Week). Some people confuse this with the `cron` format that includes a "year" or "seconds" field used by other scheduling systems, but standard Linux cron always uses exactly 5 fields.
- **Forgetting to start the cron daemon** — especially in containers or minimal installations where services don't auto-start.
- **Not making scripts executable** — writing a perfect script but forgetting `chmod +x` is a classic mistake. Cron won't give you an obvious error; the job just silently fails.
- **Using relative paths in cron scripts** — cron jobs run with a minimal environment and a different working directory. Always use absolute paths (like `/opt/scripts/backup.sh`, not `./backup.sh`).
- **Not testing manually before blaming cron** — if the script doesn't work when you run it by hand, it definitely won't work under cron. Always test the script directly first.
