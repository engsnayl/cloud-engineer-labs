#!/bin/bash
# =============================================================================
# Fault Injection: Disk Full
# Creates realistic files that consume disk space across multiple directories
# Simulates a server where logs, backups, and temp files have grown unchecked
# =============================================================================

# --- Disk Hog 1: Application log that has grown out of control ---
# A single massive log file — the most common real-world cause of disk full
{
    for i in $(seq 1 80000); do
        echo "[2025-02-$(printf '%02d' $((RANDOM % 28 + 1)))T$(printf '%02d' $((RANDOM % 24))):$(printf '%02d' $((RANDOM % 60))):$(printf '%02d' $((RANDOM % 60))).000Z] INFO  com.reports.engine.ReportGenerator - Processing report request id=$((RANDOM))$((RANDOM)) user=user$((RANDOM % 500)) type=quarterly status=generating"
    done
} > /var/log/myapp/application.log

# --- Disk Hog 2: Old rotated debug logs that were never cleaned up ---
# In production, logrotate should handle this but it wasn't configured
for n in 1 2 3 4 5; do
    dd if=/dev/urandom bs=1024 count=5120 of="/var/log/myapp/debug.log.${n}" 2>/dev/null
done

# --- Disk Hog 3: Old backup archives that nobody cleaned up ---
# Daily database backups — only the latest should be kept
for day in 01 04 07 10 13 16 19; do
    dd if=/dev/urandom bs=1024 count=10240 of="/opt/backups/db-backup-2025-01-${day}.tar.gz" 2>/dev/null
done

# --- Disk Hog 4: Stale temp files from crashed report generation ---
# The app creates temp files in /tmp but doesn't clean up on crash
for i in $(seq 1 20); do
    dd if=/dev/urandom bs=1024 count=1024 of="/tmp/reports/report-draft-$(printf '%04d' $i).tmp" 2>/dev/null
done

# --- NOT a disk hog: legitimate application data (do NOT delete) ---
echo '{"version": "2.1.0", "db_host": "db.internal", "db_port": 5432}' > /var/lib/myapp/config.json
dd if=/dev/urandom bs=1024 count=512 of="/var/lib/myapp/data/reports.db" 2>/dev/null
echo "App is healthy" > /var/lib/myapp/status.txt

echo "Disk space consumed. Application will fail with 'No space left on device'."
