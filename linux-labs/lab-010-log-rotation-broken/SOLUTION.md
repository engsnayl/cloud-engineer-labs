# Solution Walkthrough — Log Rotation Broken

## The Problem

Application log files have grown massively (80MB, 50MB, and 30MB) because logrotate — the tool that's supposed to keep log files at a manageable size — is misconfigured. There are **two issues** with the logrotate configuration:

1. **Wrong path in the config** — the config file targets `/var/log/application/*.log`, but the actual log files are in `/var/log/app/*.log`. Because of this path mismatch, logrotate never finds the logs it's supposed to rotate.
2. **Missing closing brace** — the logrotate configuration block is opened with `{` but never closed with `}`. This is a syntax error that causes logrotate to reject the entire configuration file, even if the path were correct.

Until these issues are fixed and logrotate is run, the log files will just keep growing until they fill the disk.

## Thought Process

When log files are too large and logrotate isn't working, an experienced engineer checks:

1. **How big are the files?** Use `du -sh /var/log/app/*` to see the damage.
2. **Does a logrotate config exist?** Check `/etc/logrotate.d/` for an application-specific config file.
3. **Is the config valid?** Use `logrotate -d /etc/logrotate.d/app` to do a dry run — this tests the config without actually rotating anything. It will report syntax errors and path problems.
4. **Fix and force** — after fixing the config, use `logrotate -f` to force an immediate rotation rather than waiting for the next scheduled run.

The `-d` (debug/dry-run) flag is the key diagnostic tool for logrotate — it shows you exactly what logrotate would do without actually doing it, and it reports any errors in the configuration.

## Step-by-Step Solution

### Step 1: Check the current log file sizes

```bash
du -sh /var/log/app/*
```

**What this does:** Shows the size of each file in the application log directory in human-readable format. You'll see files ranging from 30MB to 80MB — far too large for log files that should be rotated at 10MB.

### Step 2: Look at the current logrotate config

```bash
cat /etc/logrotate.d/app
```

**What this does:** Shows the logrotate configuration file. You'll see two problems:
- The path is `/var/log/application/*.log` — but the actual logs are in `/var/log/app/`
- The configuration block has an opening `{` but no closing `}`

### Step 3: Test the broken config to see the errors

```bash
logrotate -d /etc/logrotate.d/app
```

**What this does:** Runs logrotate in debug (dry-run) mode. The `-d` flag means "don't actually rotate anything, just show what you would do and report any errors." This will show error messages about the syntax problem and the fact that no matching log files were found (because the path is wrong).

### Step 4: Fix the logrotate configuration

```bash
cat > /etc/logrotate.d/app << 'EOF'
/var/log/app/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
}
EOF
```

**What this does:** Replaces the broken configuration with a corrected version. The two fixes are:
- Changed the path from `/var/log/application/*.log` to `/var/log/app/*.log` (matching where the logs actually are)
- Added the closing `}` brace

Here's what each directive means:
- `daily` — check the log files once a day
- `rotate 5` — keep up to 5 old rotated copies
- `compress` — compress rotated files with gzip to save space
- `missingok` — don't error if a log file is missing
- `notifempty` — skip rotation if the log file is empty
- `size 10M` — only rotate files larger than 10MB

### Step 5: Verify the fixed config

```bash
logrotate -d /etc/logrotate.d/app
```

**What this does:** Runs the dry-run test again. This time it should succeed — you'll see logrotate planning to rotate each of the oversized log files. No errors means the config is valid.

### Step 6: Force an immediate rotation

```bash
logrotate -f /etc/logrotate.d/app
```

**What this does:** Forces logrotate to rotate the logs right now, regardless of the size threshold or schedule. The `-f` flag means "force." This will:
1. Rename `app.log` to `app.log.1`
2. Create a new, empty `app.log`
3. Compress the old `app.log.1` to `app.log.1.gz`
4. Do the same for `access.log` and `error.log`

### Step 7: Verify the rotation worked

```bash
ls -lh /var/log/app/
```

**What this does:** Lists the log directory with human-readable file sizes. You should see:
- New, small (or empty) `.log` files
- Rotated copies like `.log.1` or `.log.1.gz`
- The active log files should all be well under 10MB

### Step 8: Confirm no log files exceed the size limit

```bash
find /var/log/app/ -name "*.log" -size +10M
```

**What this does:** Searches for any active `.log` files larger than 10MB. This should return nothing (no output), confirming all log files are now under the size limit.

## Docker Lab vs Real Life

- **Automatic scheduling:** In this lab, logrotate doesn't run automatically because Docker containers don't have cron or systemd timers by default. On a real server, logrotate is triggered daily by a cron job (usually at `/etc/cron.daily/logrotate`) or a systemd timer (`logrotate.timer`).
- **Log management at scale:** In production, application logs are often shipped to a centralized logging system (ELK stack, Splunk, CloudWatch Logs, Datadog) in real time. Logrotate still matters for the local copies, but it's not the only line of defense against disk space issues.
- **copytruncate vs create:** When applications hold log files open (which is very common), you should add `copytruncate` to the logrotate config. This copies the log file, then truncates the original to zero — so the application's file handle remains valid. Without it, logrotate renames the file and the application keeps writing to the renamed file (now invisible to you).
- **Logrotate state file:** Logrotate tracks the last rotation time in `/var/lib/logrotate/status`. If you delete this file, logrotate will rotate everything on the next run regardless of when it was last rotated.

## Key Concepts Learned

- **`logrotate -d` (dry run) is the diagnostic command** — always test your config before applying it. It shows exactly what logrotate would do and reports any errors.
- **`logrotate -f` forces immediate rotation** — useful for testing and for emergency cleanup when logs have grown too large.
- **Path accuracy is critical** — logrotate won't warn you if no files match its glob pattern (with `missingok`). A typo in the path means logs silently never get rotated.
- **Logrotate configs must have matching braces** — the `{` and `}` delimit the configuration block. A missing brace is a syntax error that invalidates the entire config file.
- **Log rotation is preventive maintenance** — without it, log files will eventually fill the disk and crash your application or even the entire server.

## Common Mistakes

- **Fixing the path but not the syntax error (or vice versa)** — both issues must be fixed. The dry-run test (`logrotate -d`) will catch either problem.
- **Not running `logrotate -f` after fixing the config** — fixing the config prevents future growth, but doesn't clean up the existing oversized files. You need to force an immediate rotation.
- **Forgetting `missingok`** — without this directive, logrotate will error and stop if any of the matched files don't exist (for example, if `error.log` hasn't been created yet). This can prevent rotation of all files in the config block.
- **Not testing with `-d` first** — jumping straight to `-f` with a broken config wastes time and can cause unexpected behavior. Always dry-run first.
- **Assuming logrotate runs automatically in all environments** — it doesn't start by default in Docker containers, minimal installations, or some cloud instances. Always verify that the cron job or systemd timer exists.
