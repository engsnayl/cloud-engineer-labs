# Lab 010 — Log Rotation Broken: Solution Walkthrough

---

## TLDR — What's Actually Wrong Here (Plain English)

Your application is supposed to automatically tidy up its own log files — like a bin that empties itself every week. The tool that does this is called **logrotate**. It reads a config file that tells it where the logs are, how big they're allowed to get, and what to do when they get too big.

In this lab, two things are broken:

1. **The config is looking for logs in the wrong folder.** It's pointing at `/var/log/application/` but the logs actually live in `/var/log/app/`. Because of this, logrotate runs but finds nothing, so the log files just keep growing unchecked.

2. **The config file has a syntax error.** It opens a configuration block with `{` but forgets to close it with `}`. Even if the path were correct, logrotate would refuse to run because the file is broken.

**The fix:** Correct the folder path, add the missing closing brace, and force logrotate to run immediately to clean up the mess that's already built up.

---

## Your Ticket

> **Incident:** Application log files are growing without bound. Disk space on the application server is being consumed rapidly. Logrotate has been configured but does not appear to be working. Investigate and resolve.

You've been handed this ticket. You don't know yet what's broken. Here's how a real engineer would work through it.

---

## The Investigative Learning Pathway

### Stage 1 — Understand the Scope of the Problem

**Your first question when you get a "logs out of control" ticket is: how bad is it right now?**

Before you touch any config, you need to see what you're dealing with. How large are the log files? Are they all massive, or just one of them?

```bash
du -sh /var/log/app/*
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `du` | "Disk Usage" — reports how much disk space files or directories are using |
| `-s` | "Summarise" — give one total per item rather than listing every sub-item |
| `-h` | "Human-readable" — show sizes as KB, MB, GB rather than raw byte counts |
| `/var/log/app/*` | The wildcard `*` means "every file inside this directory" |

**What you're expecting to see:** Small log files (ideally a few KB to a few MB). What you'll actually see is files in the 30MB–80MB range — far larger than they should be if rotation were working.

**What this tells you:** Logrotate is either not running, or not finding these files. Time to check the config.

---

### Stage 2 — Find and Read the Logrotate Configuration

**Your next question: does a logrotate config actually exist for this application?**

Logrotate configuration files for individual applications live in `/etc/logrotate.d/`. Each application that wants managed log rotation drops a config file in there.

```bash
ls /etc/logrotate.d/
```

You'll see a file called `app`. Let's read it:

```bash
cat /etc/logrotate.d/app
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `cat` | "Concatenate" — prints the contents of a file to the terminal |
| `/etc/logrotate.d/app` | The logrotate config file for this application |

**What you're looking for:** A valid configuration block that targets the correct log file path.

**What you'll actually see:**

```
/var/log/application/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
```

**Spot the problems:**

- **Wrong path:** The config says `/var/log/application/` — but you just confirmed the log files are in `/var/log/app/`. One character difference. Logrotate looks in the wrong place, finds nothing, and silently moves on (thanks to `missingok`).
- **Missing closing brace:** The block opens with `{` on the first line but there's no `}` to close it. This is a syntax error.

**Do you need to investigate further before you're confident enough to fix it?** Yes — use logrotate's own diagnostic tool to confirm what you're seeing.

---

### Stage 3 — Let Logrotate Tell You What's Wrong Itself

**Your next question: can I get logrotate to validate this config and show me the errors explicitly, without actually changing anything?**

Yes. Logrotate has a debug mode specifically for this purpose.

```bash
logrotate -d /etc/logrotate.d/app
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `logrotate` | The log rotation tool itself |
| `-d` | "Debug" mode — dry run only, shows what logrotate would do without actually doing it. No files are touched. |
| `/etc/logrotate.d/app` | The specific config file to test |

**What you'll actually see — and how to read it:**

```
WARNING: logrotate in debug mode does nothing except printing debug messages!
reading config file /etc/logrotate.d/app
warning: 'size' overrides previously specified 'daily'
Handling 1 logs
rotating pattern: /var/log/application/*.log  10485760 bytes (5 rotations)
empty log files are not rotated, old logs are removed
considering log /var/log/application/*.log
```

This output doesn't scream "broken" — which is the trap. You have to know how to read it. Here's what each line is telling you:

- **`rotating pattern: /var/log/application/*.log`** — this is the path logrotate is using. Look at it carefully. You already know from Step 1 that the logs live in `/var/log/app/` — not `/var/log/application/`. The bug is right here in plain sight.
- **`considering log /var/log/application/*.log`** — logrotate is "considering" the pattern, but you'll notice it never lists any actual files beneath this line. On a working config you'd see each individual log file named. Silence here means **zero files matched**. Logrotate found nothing and quietly moved on.
- **`warning: 'size' overrides previously specified 'daily'`** — this is a minor config quality warning (having both `size` and `daily` in the same block means `size` wins). It's not one of the bugs we introduced, but worth noting.

> **Important:** On this version of logrotate, the missing closing brace does not produce a hard error in `-d` mode — it tolerates it. Don't rely on logrotate to shout about syntax problems. The more reliable signal is the path mismatch and the absence of individual files being listed.

**What you've confirmed:** The config is targeting the wrong directory. You can see the wrong path in the output and you can see that no actual files were processed. That's enough to fix.

---

### Stage 4 — Fix the Configuration

**Now you know exactly what's wrong. Time to correct both issues in one go.**

You're going to overwrite the broken config file with a corrected version:

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

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `cat >` | Redirect output into a file. Unlike `>>` (append), `>` overwrites the file completely |
| `/etc/logrotate.d/app` | The file being overwritten |
| `<< 'EOF'` | "Here document" — everything typed between `<< 'EOF'` and the closing `EOF` is treated as input. The single quotes around `'EOF'` prevent any variable expansion inside the block |
| `EOF` | Marks the end of the here document |

**What changed in the config:**

| Was | Now | Why |
|-----|-----|-----|
| `/var/log/application/*.log` | `/var/log/app/*.log` | Corrected path to match where logs actually live |
| (no closing brace) | `}` added | Fixed the syntax error |

**What each directive inside the config block means:**

| Directive | What it does |
|-----------|--------------|
| `daily` | Check these files once per day |
| `rotate 5` | Keep up to 5 old rotated copies before deleting the oldest |
| `compress` | Compress rotated files with gzip (saves disk space) |
| `missingok` | Don't throw an error if a log file is missing — just skip it |
| `notifempty` | Don't rotate a log file if it's completely empty |
| `size 10M` | Only rotate files that are larger than 10MB |

---

### Stage 5 — Verify the Fixed Config Before Applying It

**Before you force anything, confirm the fix actually worked by running the debug mode again.**

```bash
logrotate -d /etc/logrotate.d/app
```

This time look for two things:

1. **The path has changed** — you should now see `rotating pattern: /var/log/app/*.log` in the output, not `/var/log/application/`
2. **Individual files are now listed** — unlike before, logrotate should now list each actual log file it found and intends to rotate

```
rotating pattern: /var/log/app/*.log  10485760 bytes (5 rotations)
considering log /var/log/app/app.log
  log does not need rotating (log is already rotated)
considering log /var/log/app/access.log
  log does not need rotating (log is already rotated)
considering log /var/log/app/error.log
  log does not need rotating (log is already rotated)
```

> **Note:** You may see "log does not need rotating" even though the files are oversized — this is because `-d` mode checks the logrotate state file, which may not exist yet in this container. That's fine. What matters is that the correct path is now being used and individual files are being found and considered. The `-f` flag in the next step overrides all of this.

**This is good practice in real life too** — you always validate config changes before applying them, especially for tooling that touches production logs.

---

### Stage 6 — Force an Immediate Rotation

**The config is now valid and targeting the right files. But the existing oversized log files won't shrink on their own — you need to trigger a rotation manually.**

Normally logrotate runs on a schedule (daily, via cron or systemd). Since you need to clean up now:

```bash
logrotate -f /etc/logrotate.d/app
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `logrotate` | The log rotation tool |
| `-f` | "Force" — run rotation right now, regardless of schedule or whether files meet the size threshold |
| `/etc/logrotate.d/app` | The config file to use |

**What logrotate does when it runs:**

1. Renames `app.log` → `app.log.1`
2. Creates a new, empty `app.log` for the application to write to going forward
3. Compresses `app.log.1` → `app.log.1.gz`
4. Repeats this for `access.log` and `error.log`

---

### Stage 7 — Confirm the Rotation Worked

**Two checks to close the ticket with confidence.**

**Check 1 — List the directory:**

```bash
ls -lh /var/log/app/
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `ls` | List directory contents |
| `-l` | "Long" format — show permissions, owner, size, and timestamp |
| `-h` | "Human-readable" — show file sizes in KB/MB/GB |

You should see new, small (or empty) `.log` files alongside `.log.1.gz` compressed archives.

**Check 2 — Confirm no active log files exceed the size limit:**

```bash
find /var/log/app/ -name "*.log" -size +10M
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `find` | Search for files matching criteria |
| `/var/log/app/` | The directory to search in |
| `-name "*.log"` | Only match files ending in `.log` (the active log files, not the rotated archives) |
| `-size +10M` | Only match files larger than 10MB. The `+` means "greater than" |

**Expected result:** No output. Silence means all active log files are now under the 10MB limit. If any filenames are returned, rotation didn't work for those files and you need to investigate further.

---

## Environment Notes — Docker vs Real Life

- **Why logrotate doesn't run automatically in this lab:** Docker containers don't have cron or systemd timers running by default. On a real Linux server, logrotate is triggered by either a cron job at `/etc/cron.daily/logrotate` or a systemd timer (`logrotate.timer`). In this lab you use `-f` to trigger it manually instead.

- **The `missingok` directive and silent failures:** `missingok` tells logrotate not to error if a matched file is missing. This is sensible for production use (not every log file exists on every server), but it also means a misconfigured path fails silently — logrotate just shrugs and moves on without telling you nothing matched. This is why the path error in this lab went unnoticed.

- **`copytruncate` for applications that hold files open:** In real production environments, long-running applications (Java services, nginx, etc.) hold log file handles open. If logrotate renames the file, the application keeps writing to the renamed file — and the new empty file stays empty. The `copytruncate` directive solves this: it copies the log, then truncates the original to zero bytes so the application's file handle stays valid.

- **Logrotate's state file:** Logrotate records when it last rotated each file in `/var/lib/logrotate/status`. If this file is deleted, logrotate treats all files as never-rotated and will rotate everything on the next run regardless of the schedule.

- **In production, local log rotation is rarely the whole story:** Logs are usually also shipped to a centralised system (ELK stack, CloudWatch Logs, Datadog, Splunk) in real time. Logrotate manages the local copies on disk, but it's one layer of a broader observability setup.

---

## Key Concepts to Take Away

- **`logrotate -d` is your diagnostic tool** — always test a logrotate config with `-d` before applying it. It shows exactly what would happen and reports errors, without touching any files.
- **`logrotate -f` forces immediate rotation** — essential for emergency cleanup and for testing your config against real log files.
- **Path accuracy is everything** — a typo in the log path means logrotate silently does nothing (with `missingok`). You won't get an error message, the logs will just keep growing.
- **Logrotate config blocks must have matching braces** — the `{` and `}` delimit the entire configuration block. A missing brace is a hard syntax error that invalidates the whole file.
- **Log rotation is preventive maintenance** — left unmanaged, log files fill disks. A full disk can crash your application, your database, or your entire server.

---

## Common Mistakes to Avoid

- **Fixing only one of the two bugs** — both the path and the missing brace must be corrected. If you fix the path but not the brace, the config is still syntactically invalid. If you fix the brace but not the path, logrotate still finds nothing. The dry-run test (`logrotate -d`) catches either issue.
- **Forgetting to force a rotation after fixing the config** — fixing the config prevents future growth but doesn't clean up the existing oversized files. Always follow a config fix with `logrotate -f`.
- **Not running `-d` before `-f`** — jumping straight to force-rotate with a still-broken config wastes time and can produce unexpected results. Dry-run first, always.
- **Assuming `missingok` means "warn me if nothing matches"** — it doesn't. It means "stay quiet and carry on". A misconfigured path with `missingok` is a silent failure.
- **Assuming logrotate runs automatically everywhere** — it doesn't. Containers, minimal cloud instances, and some server images don't have cron or systemd timers configured. Always check that the scheduled trigger actually exists.

---

## Cleanup / Reset

To reset the lab so it can be run again from Step 1:

```bash
# Restore the broken logrotate config
cat > /etc/logrotate.d/app << 'EOF'
/var/log/application/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
EOF

# Remove any rotated/compressed archives from this run
rm -f /var/log/app/*.gz /var/log/app/*.log.1

# Regenerate large log files to restore the broken starting state
# (run whatever script the lab setup uses to inflate the logs)
```

> **Note:** The exact log inflation command depends on how the lab's Docker container generates the starting state. Check the lab setup script if you need to recreate the oversized files from scratch.
