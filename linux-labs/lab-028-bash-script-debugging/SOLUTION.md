# Solution Walkthrough — Bash Script Debugging

## The Problem

A health check and log rotation script has been silently failing. There are **nine bugs**:

1. **Spaces around = in variable assignment** — `HOSTNAME = $(hostname)` fails silently. Bash treats this as running a command called `HOSTNAME` with arguments `=` and the output of `hostname`.
2. **No error handling** — missing `set -euo pipefail` means errors are swallowed.
3. **Unquoted variables in conditions** — `[ $usage -gt 90 ]` breaks if `$usage` is empty.
4. **Float comparison with integer operator** — `-gt` only works with integers. `printf "%.0f"` handles this but need to verify.
5. **grep exit code with set -e** — `grep -c "ERROR"` returns exit code 1 when no matches, killing the script.
6. **Wrong find -mtime value and -delete order** — using 30 instead of `$MAX_LOG_AGE_DAYS`, and `-delete` before `-print` means nothing is printed.
7. **Unquoted LOG_DIR in find** — `find $LOG_DIR` breaks with spaces.
8. **Report directory not created** — if `/var/reports` doesn't exist, the script fails.
9. **No meaningful exit code** — script should signal success/warning status.

## The Fixed Script

```bash
#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/app"
REPORT_DIR="/var/reports"
MAX_LOG_AGE_DAYS=7
HOSTNAME=$(hostname)
REPORT_FILE="${REPORT_DIR}/health-$(date +%Y%m%d-%H%M%S).txt"
WARNING_FLAG=0

mkdir -p "$REPORT_DIR"

check_disk_usage() {
    echo "=== Disk Usage ===" >> "$REPORT_FILE"
    df -h >> "$REPORT_FILE"
    
    local usage
    usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ "$usage" -gt 90 ]]; then
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

## Key Concepts Learned

- **No spaces in variable assignment** — `VAR=value` not `VAR = value`. This is the most common Bash gotcha for people coming from other languages.
- **Always use set -euo pipefail** — catches undefined variables, failed commands, and pipe failures. Essential for production scripts.
- **Handle grep exit codes** — `grep` returns 1 when no matches. Use `grep ... || true` or `if grep ...` to prevent `set -e` from killing the script.
- **Always quote variables** — `"$VAR"` prevents word splitting and globbing. This is the single most important Bash habit.
- **Use shellcheck** — it catches 90% of common Bash mistakes automatically. Run it on every script.
- **mkdir -p before writing files** — never assume directories exist. Create them defensively.

## Common Mistakes

- **Testing scripts without set -e** — scripts "work" in testing but fail silently in cron because errors are swallowed.
- **Forgetting that grep returns non-zero on no match** — this breaks `set -e` scripts constantly.
- **Using [ ] instead of [[ ]]** — double brackets are safer: they handle empty variables and don't require quoting inside.
- **Hardcoding values instead of using variables** — the MAX_LOG_AGE_DAYS variable exists but the find command used a hardcoded 30.
- **Not logging script errors** — redirect stderr to a log file so cron job failures are visible.
