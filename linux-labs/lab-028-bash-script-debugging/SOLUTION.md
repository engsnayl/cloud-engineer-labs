# Solution Walkthrough — Lab 028: Bash Script Debugging

---

## TLDR Summary

A health check and log rotation script is running via cron but silently doing nothing useful. It looks like it runs fine — no error emails from cron, no complaints — but the reports it should be generating are empty or missing, variables are being swallowed, and the log cleanup isn't working. The root cause is **nine bugs** ranging from a basic Bash syntax mistake that kills the first variable assignment, through to missing error handling that hides every subsequent failure. The fix involves reading through the script line by line, running it manually to see what breaks, and correcting each issue in the order you discover them.

---

## Background: Why This Script Matters

In production, health check scripts like this one typically run on a cron schedule (e.g. every hour). They check disk usage, memory, scan for error logs, and rotate old log files. When they fail silently — which Bash scripts love to do — nobody notices until disk fills up, logs pile up, or an outage happens and the reports that should have been there don't exist.

The reason Bash scripts fail silently so often is that **Bash does not stop on errors by default**. If a command fails, Bash just moves on to the next line. This is the opposite of most programming languages, and it's the single biggest trap for people writing production shell scripts.

---

## Step-by-Step Investigative Learning Pathway

You've been given a ticket: *"The health check script hasn't been generating reports. It's in cron but nothing is being produced. Please investigate and fix."*

This is how you work through it.

---

### Step 1: Get Your Bearings — What Are We Actually Looking At?

Before touching anything, find and read the script top to bottom. Don't try to fix anything yet. You're building a mental model of what this script is *supposed* to do.

First, find the script:

```bash
find / -name "*.sh" -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null
```

| Command Part | What It Does |
|---|---|
| `find /` | Search the entire filesystem starting from root |
| `-name "*.sh"` | Only match files ending in `.sh` |
| `-not -path "/proc/*"` | Skip the `/proc` virtual filesystem (not real files) |
| `-not -path "/sys/*"` | Skip the `/sys` virtual filesystem |
| `2>/dev/null` | Suppress "permission denied" errors so output is clean |

This reveals the script lives at `/opt/scripts/healthcheck.sh`. Now read it:

```bash
cat /opt/scripts/healthcheck.sh
```

| Command Part | What It Does |
|---|---|
| `cat` | Prints the entire contents of a file to the terminal |

As you read through it, make a note of what the script intends:
- It sets some variables (LOG_DIR, REPORT_DIR, MAX_LOG_AGE_DAYS, HOSTNAME)
- It creates a report file
- It has four functions: check_disk_usage, check_memory, check_error_logs, rotate_logs
- It calls those functions and writes output to the report

**Key question at this point**: Has this script *ever* worked, or has it always been broken? Check if any old reports exist:

```bash
ls -la /var/reports/
```

If the directory exists but is empty — no reports have ever been successfully generated. That's a clue that the script has been broken from the start.

---

### Step 2: Run It Manually and Watch What Happens

Cron swallows output. Running the script manually in your terminal will show you errors that cron was hiding.

```bash
bash /opt/scripts/healthcheck.sh
```

| Command Part | What It Does |
|---|---|
| `bash` | Explicitly runs the script with the Bash interpreter |
| `/opt/scripts/healthcheck.sh` | Full path to the script — you need the full path because you're not in the same directory |

**What to watch for**: Does it error out immediately? Does it run but produce nothing? Does it complete silently? Each of these tells you something different.

You'll see something like:

```
/opt/scripts/healthcheck.sh: line 10: HOSTNAME: command not found
Report saved to /var/reports/health-20260330-213222.txt
```

Two things to note here: it errored on line 10, but then **carried on and said "Report saved"**. The script didn't stop when it hit an error. Hold that thought.

For even more visibility, run it in debug mode:

```bash
bash -x /opt/scripts/healthcheck.sh
```

| Command Part | What It Does |
|---|---|
| `-x` | Prints every line as it executes, with the expanded variable values — so you can see exactly what Bash is doing at each step |

This is your best friend for debugging shell scripts. Every line the script runs gets printed with a `+` prefix, showing you the actual values of variables after expansion.

**Important**: `bash -x` only shows you what's happening — it doesn't tell you what's *wrong*. If a line runs without crashing, `-x` will happily print it and move on. It's blind to logic bugs like using the wrong variable value or having conditions that will only fail under certain circumstances. It catches crashes, not bad logic. The remaining bugs after the first two are found by **reading the script and reasoning about it**.

---

### Step 3: The First Bug — The Variable Assignment (Spaces Around =)

Look at line 10 in the script:

```bash
HOSTNAME = $(hostname)
```

The debug trace shows `+ HOSTNAME = 306e509e802d` followed by `command not found`. Bash expanded `$(hostname)` correctly but then failed because of the spaces.

**In Bash, variable assignment has no spaces around the `=` sign.** This is non-negotiable syntax:

```bash
# WRONG — Bash sees this as: run a command called "HOSTNAME" with arguments "=" and the output of hostname
HOSTNAME = $(hostname)

# RIGHT — Bash sees this as: assign the output of hostname to the variable HOSTNAME
HOSTNAME=$(hostname)
```

**How would you know this?** The `bash -x` output and the "command not found" error point you directly at this line. If you know Bash syntax, the spaces immediately stand out. If you don't, the error message is your clue — Bash is trying to *run* `HOSTNAME` as a command, which means it's not treating this as an assignment.

**Note:** The script still appeared to work because `$HOSTNAME` is a built-in environment variable that already exists in Bash. So the assignment failed, but `$HOSTNAME` still had a value from the environment. This is a coincidence that masks the bug.

**The fix:**

```bash
HOSTNAME=$(hostname)
```

Remove the spaces either side of `=`.

---

### Step 4: Why Didn't the Script Stop? — Missing Error Handling

The assignment on line 10 errored out, but the script carried on and generated a report anyway. Ask yourself: *"Why didn't it stop?"*

The answer: **The script has no error handling.** Look at the very top — there's no `set -euo pipefail`.

Without this, Bash's default behaviour is:
- A command fails → carry on to the next line anyway
- A variable is undefined → treat it as an empty string, no error
- A command in a pipeline fails → ignore it if the last command succeeded

This is why the script was "running" in cron but doing nothing useful. Every failure was being silently swallowed.

**The fix** — add this immediately after the shebang (`#!/bin/bash`) and comments:

```bash
set -euo pipefail
```

| Flag | What It Does |
|---|---|
| `-e` | Exit immediately if any command returns a non-zero (error) exit code |
| `-u` | Treat unset/undefined variables as an error instead of silently using an empty string |
| `-o pipefail` | If any command in a pipeline fails, the whole pipeline's exit code reflects the failure (not just the last command's exit code) |

**Why does this matter?** Once you add `set -euo pipefail`, the script will now *actually stop and tell you* when something is wrong. But it also means you need to be careful — some commands legitimately return non-zero exit codes (like `grep` when it finds no matches), so you'll need to handle those. More on that below.

---

### Step 5: Run Again — Confirm the First Two Fixes Work

After adding `set -euo pipefail` and fixing the variable assignment, run the script again:

```bash
bash -x /opt/scripts/healthcheck.sh
```

You should see `+ HOSTNAME=b86384970a13` (clean assignment, no error) and `+ set -euo pipefail` at the top.

Now — the script may run all the way through without `set -e` killing it. That happens when every command succeeds at runtime. But this doesn't mean the remaining bugs don't exist — it means the **conditions that trigger them aren't present right now**. For example, `grep -c "ERROR"` found 1 match so it returned exit code 0. If the log had zero errors, the script would have died. These are time-bomb bugs.

**From this point on, the remaining bugs are found by reading the script and reasoning, not by watching it crash.**

---

### Step 6: Unquoted Variables in Conditions

Inside `check_disk_usage()`, look at the conditional:

```bash
if [ $usage -gt 90 ]; then
```

**The problem:** If `$usage` is empty for any reason (the `df` command failed, the `awk` didn't extract a number, etc.), this line becomes:

```bash
if [ -gt 90 ]; then
```

Which is a syntax error: `[: -gt: unary operator expected`.

**How would you know this?** It won't crash right now because `$usage` has a value (17). But if you think about edge cases — what if this runs on a system where `df` returns unexpected output? — the unquoted variable is a risk.

**The fix:**

```bash
if [ "$usage" -gt 90 ]; then
```

| Change | Why |
|---|---|
| `"$usage"` instead of `$usage` | Quoting prevents word splitting if the value contains spaces, and prevents the empty-string syntax error |

The `check_memory()` function already uses `[[ ]]` (double brackets) which handles empty variables more safely, but you should still quote the variable there too for consistency.

---

### Step 7: grep Kills the Script When There Are No Errors

This is one of the most common Bash traps. Look at `check_error_logs()`:

```bash
local error_count=$(grep -c "ERROR" "$LOG_DIR/app-current.log")
```

**The problem:** `grep` returns exit code 1 when it finds *zero matches*. That's not an error — it just means there were no ERRORs in the log file. But `set -e` doesn't care — exit code 1 means "something failed", so the script dies.

**How would you know this?** In the current lab run, `grep` found 1 match so it returned 0 and everything was fine. But if you think about it — what happens on a good day when there are zero errors in the log? The script would crash. This is a time-bomb bug.

**The fix:**

```bash
error_count=$(grep -c "ERROR" "$LOG_DIR/app-current.log" || true)
```

| Command Part | What It Does |
|---|---|
| `grep -c "ERROR"` | Counts lines matching "ERROR" in the file |
| `\|\| true` | If grep returns non-zero (no matches), run `true` instead — which always returns 0, preventing `set -e` from killing the script |

This `|| true` pattern is the standard Bash idiom for "this command might legitimately return non-zero and that's OK."

---

### Step 8: The Log Rotation Is Broken — Hardcoded Value and Wrong Order

Now look at `rotate_logs()`. There are two bugs in the `find` command:

```bash
find $LOG_DIR -name "*.log" -mtime +30 -delete -print
```

**Bug 1: Hardcoded `+30` instead of the variable**

The script has `MAX_LOG_AGE_DAYS=7` defined at the top, but the `find` command uses a hardcoded `30`. This means it's deleting logs older than 30 days instead of the configured 7. In the lab, the container was just created so no files are older than 30 days — which is why the find command produces no output and the rotation appears to do nothing.

**How would you know this?** By reading the script and noticing that `MAX_LOG_AGE_DAYS` exists but isn't being used anywhere. In a real investigation, you might notice logs piling up that are 8-29 days old and wonder why they're not being cleaned up.

**Bug 2: `-delete` before `-print`**

The order of `find` actions matters. `-delete -print` means: delete the file first, then try to print it. The `-print` may not output anything useful because the file is already gone. Swap the order so you log what you're deleting before you delete it.

**The fix:**

```bash
find "$LOG_DIR" -name "*.log" -mtime +"$MAX_LOG_AGE_DAYS" -print -delete >> "$REPORT_FILE"
```

| Change | Why |
|---|---|
| `"$LOG_DIR"` instead of `$LOG_DIR` | Quoting protects against paths with spaces |
| `+"$MAX_LOG_AGE_DAYS"` instead of `+30` | Uses the variable defined at the top — so changing the config actually changes the behaviour. Note the `$` is required to expand the variable |
| `-print -delete` instead of `-delete -print` | Print the filename first (so it goes into the report), then delete the file |

**Command breakdown for the whole line:**

| Part | What It Does |
|---|---|
| `find` | Searches for files/directories matching criteria |
| `"$LOG_DIR"` | The directory to search in |
| `-name "*.log"` | Only match files ending in `.log` |
| `-mtime +"$MAX_LOG_AGE_DAYS"` | Only match files modified more than N days ago (the `+` means "more than") |
| `-print` | Output the filename to stdout |
| `-delete` | Delete the matched file |
| `>> "$REPORT_FILE"` | Append the printed filenames to the report |

---

### Step 9: Shellcheck — Declare and Assign Separately (SC2155)

After fixing all the logic bugs, run `shellcheck` against the script:

```bash
shellcheck /opt/scripts/healthcheck.sh
```

| Command Part | What It Does |
|---|---|
| `shellcheck` | A static analysis tool for shell scripts — it catches common bugs and bad practices without running the script |

You can also run this from the Pi if shellcheck isn't in the container:

```bash
docker exec -it lab028-scripting shellcheck /opt/scripts/healthcheck.sh
```

Shellcheck will flag SC2155 on every line where `local` and a command substitution are on the same line:

```bash
# FLAGGED — local masks the exit code of the command
local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')

# FIXED — declare first, then assign
local usage
usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
```

**Why does this matter?** The `local` keyword has its own exit code (always 0). When you combine `local` with `$(command)` on one line, `local`'s exit code overwrites the command's exit code. So if the command inside `$(...)` fails, you'd never know — `local` returns 0 regardless.

By splitting them, `set -e` can now catch a failure in the assignment line because `local` isn't masking it.

Apply this split to all four variables: `usage`, `mem_percent`, `error_count`, and `count`.

---

### Step 10: Add a Meaningful Exit Code

The original script just ends — it doesn't tell the caller whether the health check found warnings or not. For a cron job, this matters because monitoring tools can check the exit code to decide whether to alert.

**The fix** — track a warning flag and exit with it:

At the top of the script (after the variable declarations), add:

```bash
WARNING_FLAG=0
```

In each function where a warning condition is found (disk > 90%, memory > 85%), add:

```bash
WARNING_FLAG=1
```

At the very end of the script:

```bash
exit "$WARNING_FLAG"
```

| Exit Code | Meaning |
|---|---|
| `0` | Everything healthy — no warnings |
| `1` | At least one warning was triggered |

This lets cron or a monitoring wrapper check `$?` after the script runs and decide whether to page someone.

---

### Step 11: Defensive Improvement — mkdir -p (Best Practice)

The lab container pre-creates `/var/reports/`, so this doesn't surface as a bug during the lab. But in a real deployment, if the report directory doesn't exist, the first `echo >` to the report file would fail.

Adding this line before the report file is first written makes the script self-sufficient:

```bash
mkdir -p "$REPORT_DIR"
```

| Command Part | What It Does |
|---|---|
| `mkdir` | Creates a directory |
| `-p` | Creates parent directories as needed AND doesn't error if the directory already exists |
| `"$REPORT_DIR"` | The variable holding the path — quoted in case it contains spaces |

This is a **defensive improvement**, not a bug you'd discover through diagnosis in this lab. But it's the kind of hardening that separates a script that works on one machine from a script that works everywhere.

---

## The Fully Fixed Script

```bash
#!/bin/bash
# =============================================================================
# Server Health Check and Log Rotation Script
# Runs hourly via cron — checks system health and rotates old logs
# =============================================================================
set -euo pipefail

LOG_DIR=/var/log/app
REPORT_DIR=/var/reports
MAX_LOG_AGE_DAYS=7
HOSTNAME=$(hostname)
REPORT_FILE="$REPORT_DIR/health-$(date +%Y%m%d-%H%M%S).txt"
WARNING_FLAG=0

mkdir -p "$REPORT_DIR"

check_disk_usage() {
    echo "=== Disk Usage ===" >> "$REPORT_FILE"
    df -h >> "$REPORT_FILE"
    
    local usage
    usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$usage" -gt 90 ]; then
        echo "WARNING: Disk usage at ${usage}%" >> "$REPORT_FILE"
        WARNING_FLAG=1
    fi
}

check_memory() {
    echo "=== Memory Usage ===" >> "$REPORT_FILE"
    free -h >> "$REPORT_FILE"
    
    local mem_percent
    mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [[ "$mem_percent" -gt 85 ]]; then
        echo "WARNING: Memory usage at ${mem_percent}%" >> "$REPORT_FILE"
        WARNING_FLAG=1
    fi
}

check_error_logs() {
    echo "=== Recent Errors ===" >> "$REPORT_FILE"
    
    local error_count
    error_count=$(grep -c "ERROR" "$LOG_DIR/app-current.log" || true)
    echo "Found ${error_count} errors in current log" >> "$REPORT_FILE"
}

rotate_logs() {
    echo "=== Log Rotation ===" >> "$REPORT_FILE"
    
    find "$LOG_DIR" -name "*.log" -mtime +"$MAX_LOG_AGE_DAYS" -print -delete >> "$REPORT_FILE"
    
    local count
    count=$(find "$LOG_DIR" -name "*.log" | wc -l)
    echo "Remaining log files: ${count}" >> "$REPORT_FILE"
}

echo "Health Check Report - $(date)" > "$REPORT_FILE"
echo "Host: $HOSTNAME" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_disk_usage
check_memory
check_error_logs
rotate_logs

echo "" >> "$REPORT_FILE"
echo "=== Check Complete ===" >> "$REPORT_FILE"

echo "Report saved to $REPORT_FILE"
exit "$WARNING_FLAG"
```

---

## Bug Summary Table

| # | Bug | Where | Symptom | Fix |
|---|---|---|---|---|
| 1 | Spaces around `=` in assignment | `HOSTNAME = $(hostname)` | Variable never gets set, Bash tries to run "HOSTNAME" as a command | Remove spaces: `HOSTNAME=$(hostname)` |
| 2 | No `set -euo pipefail` | Top of script | All errors silently swallowed — script appears to run fine but does nothing useful | Add `set -euo pipefail` after the shebang |
| 3 | Unquoted variable in `[ ]` | `check_disk_usage` if condition | Empty variable causes syntax error: `[: -gt: unary operator expected` | Quote: `"$usage"` |
| 4 | grep exit code 1 with `set -e` | `check_error_logs` | Script dies when log file has zero ERRORs | Add `\|\| true` after grep |
| 5 | Hardcoded `+30` instead of variable | `rotate_logs` find command | Logs older than 7 days aren't cleaned up (uses 30 instead) | Use `+"$MAX_LOG_AGE_DAYS"` |
| 6 | `-delete` before `-print` | `rotate_logs` find command | Deleted files aren't reported in the log | Swap to `-print -delete` |
| 7 | Unquoted `$LOG_DIR` in find | `rotate_logs` find command | Breaks if path contains spaces | Quote: `"$LOG_DIR"` |
| 8 | `local` masks return values (SC2155) | All four functions | Failed commands inside `$(...)` are hidden by `local`'s exit code | Split into `local var` then `var=$(...)` on separate lines |
| 9 | No meaningful exit code | End of script | Cron/monitoring can't tell if warnings were found | Track `WARNING_FLAG`, `exit "$WARNING_FLAG"` |

**Defensive improvement (not a bug in this lab):**

| # | Improvement | Why |
|---|---|---|
| 10 | `mkdir -p "$REPORT_DIR"` | The lab container pre-creates the directory, but in production the script should create its own output directory to be self-sufficient |

---

## Key Concepts Learned

**No spaces in variable assignment** — `VAR=value` not `VAR = value`. This is the most common Bash mistake for people coming from Python, JavaScript, or any language where spaces around `=` are normal or required. In Bash, spaces make it a command, not an assignment.

**Always use `set -euo pipefail`** — Without it, Bash is a silent failure machine. Every production script should have this on line 2. It catches undefined variables (`-u`), failed commands (`-e`), and pipe failures (`-o pipefail`).

**`bash -x` shows execution, not logic bugs** — It's brilliant for finding crashes and seeing variable values, but it won't tell you "that +30 should be +7" or "those variables should be quoted." Once the obvious crashes are fixed, the remaining bugs are found by reading and reasoning about the script.

**`grep` returns 1 on no match** — This isn't an error, it's just grep saying "I didn't find anything." But `set -e` treats any non-zero exit code as a failure. The `|| true` pattern handles this cleanly.

**Always quote your variables** — `"$VAR"` prevents word splitting and globbing. Unquoted variables are the source of more Bash bugs than almost anything else.

**`find` action order matters** — `-print -delete` is different from `-delete -print`. Think of `find` actions as happening left to right for each file.

**Separate `local` from assignment** — `local var=$(cmd)` masks the exit code of `cmd`. Split into `local var` then `var=$(cmd)` so `set -e` can catch failures.

**Use `shellcheck`** — It catches common Bash mistakes automatically. Run it on every script. The validator checks for shellcheck compliance, and in production it's typically part of a CI lint step.

---

## Cleanup / Reset

To re-run this lab from scratch:

```bash
# Remove any generated reports inside the container
docker exec -it lab028-scripting rm -rf /var/reports/*

# Restore the broken script from git on the Pi
cd ~/cloud-engineer-labs
git checkout -- labs/*/lab-028*/
```

This resets the script back to its broken state so you can attempt the lab again from Step 1.
