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

# --- Health Check Functions ---

check_disk_usage() {
    echo "=== Disk Usage ===" >> "$REPORT_FILE"
    df -h >> "$REPORT_FILE"
    
    local usage
	usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$usage" -gt 90 ]
    then
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

# --- Main ---

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
