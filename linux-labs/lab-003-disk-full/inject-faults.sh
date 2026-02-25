#!/bin/bash
# =============================================================================
# Fault Injection: Disk Full
# Creates realistic files that consume space on the /data tmpfs partition
# Simulates a server where logs, backups, and temp files have grown unchecked
# =============================================================================

# Create the application directory structure on the data partition
mkdir -p /data/myapp/data
mkdir -p /data/logs
mkdir -p /data/backups
mkdir -p /data/tmp

# --- Disk Hog 1: Application log that has grown out of control ---
# A single massive log file — the most common real-world cause of disk full
# Generate a small seed of realistic log lines, then repeat it to reach ~10MB fast
{
    for i in $(seq 1 500); do
        echo "[2025-02-$(printf '%02d' $((RANDOM % 28 + 1)))T$(printf '%02d' $((RANDOM % 24))):$(printf '%02d' $((RANDOM % 60))):$(printf '%02d' $((RANDOM % 60))).000Z] INFO  com.reports.engine.ReportGenerator - Processing report request id=$((RANDOM))$((RANDOM)) user=user$((RANDOM % 500)) type=quarterly status=generating"
    done
} > /tmp/_seed.log
# Repeat the seed block to reach ~10MB
for _ in $(seq 1 130); do cat /tmp/_seed.log; done > /data/logs/application.log
rm /tmp/_seed.log

# --- Disk Hog 2: Old rotated debug logs that were never cleaned up ---
# In production, logrotate should handle this but it wasn't configured
for n in 1 2 3 4 5; do
    dd if=/dev/urandom bs=1024 count=7168 of="/data/logs/debug.log.${n}" 2>/dev/null
done

# --- Disk Hog 3: Old backup archives that nobody cleaned up ---
# Daily database backups — only the latest should be kept
for day in 01 04 07 10 13 16 19; do
    dd if=/dev/urandom bs=1024 count=11264 of="/data/backups/db-backup-2025-01-${day}.tar.gz" 2>/dev/null
done

# --- Disk Hog 4: Stale temp files from crashed report generation ---
# The app creates temp files but doesn't clean up on crash
for i in $(seq 1 20); do
    dd if=/dev/urandom bs=1024 count=2048 of="/data/tmp/report-draft-$(printf '%04d' $i).tmp" 2>/dev/null
done

# --- NOT a disk hog: legitimate application data (do NOT delete) ---
echo '{"version": "2.1.0", "db_host": "db.internal", "db_port": 5432}' > /data/myapp/config.json
dd if=/dev/urandom bs=1024 count=512 of="/data/myapp/data/reports.db" 2>/dev/null
echo "App is healthy" > /data/myapp/status.txt

echo "Disk space consumed. Application will fail with 'No space left on device'."
