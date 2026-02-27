#!/bin/bash
# =============================================================================
# Server Health Check and Log Rotation Script
# Runs hourly via cron — checks system health and rotates old logs
# =============================================================================

LOG_DIR=/var/log/app
REPORT_DIR=/var/reports
MAX_LOG_AGE_DAYS=7
# BUG 1: Variable has spaces around = sign — bash doesn't allow this
HOSTNAME = $(hostname)
REPORT_FILE="$REPORT_DIR/health-$(date +%Y%m%d-%H%M%S).txt"

# BUG 2: No error handling — script should exit on errors and handle them
# Missing: set -euo pipefail or equivalent

# --- Health Check Functions ---

check_disk_usage() {
    echo "=== Disk Usage ===" >> "$REPORT_FILE"
    df -h >> "$REPORT_FILE"
    
    # BUG 3: Using single brackets and missing quotes — will break with spaces
    local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ $usage -gt 90 ]
    then
        echo "WARNING: Disk usage at ${usage}%" >> "$REPORT_FILE"
    fi
}

check_memory() {
    echo "=== Memory Usage ===" >> "$REPORT_FILE"
    free -h >> "$REPORT_FILE"
    
    # BUG 4: Wrong comparison operator — -gt is for integers, using it on a float
    local mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [[ $mem_percent -gt 85 ]]; then
        echo "WARNING: Memory usage at ${mem_percent}%" >> "$REPORT_FILE"
    fi
}

check_error_logs() {
    echo "=== Recent Errors ===" >> "$REPORT_FILE"
    
    # BUG 5: grep returns exit code 1 when no matches — this kills the script with set -e
    # Need to handle grep's exit code properly
    local error_count=$(grep -c "ERROR" "$LOG_DIR/app-current.log")
    echo "Found ${error_count} errors in current log" >> "$REPORT_FILE"
}

rotate_logs() {
    echo "=== Log Rotation ===" >> "$REPORT_FILE"
    
    # BUG 6: find command has wrong syntax — -mtime +7 deletes files OLDER than 7 days
    # but the variable isn't being used, and -delete is before -print
    find $LOG_DIR -name "*.log" -mtime +30 -delete -print >> "$REPORT_FILE"
    
    # BUG 7: Not quoting the variable — will break if LOG_DIR has spaces
    local count=$(find $LOG_DIR -name "*.log" | wc -l)
    echo "Remaining log files: ${count}" >> "$REPORT_FILE"
}

# --- Main ---

# BUG 8: Not creating the report directory if it doesn't exist
echo "Health Check Report - $(date)" > "$REPORT_FILE"
echo "Host: $HOSTNAME" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

check_disk_usage
check_memory
check_error_logs
rotate_logs

echo "" >> "$REPORT_FILE"
echo "=== Check Complete ===" >> "$REPORT_FILE"

# BUG 9: No exit code — script should exit 0 on success, non-zero on warning
echo "Report saved to $REPORT_FILE"
