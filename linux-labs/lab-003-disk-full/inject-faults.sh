#!/bin/bash
# =============================================================================
# Fault Injection: Disk Full
# Creates various large files to simulate disk space exhaustion
# =============================================================================

# Fault 1: Massive application log file (runaway logging)
dd if=/dev/urandom of=/var/log/myapp/application.log bs=1M count=80 2>/dev/null
dd if=/dev/urandom of=/var/log/myapp/application.log.1 bs=1M count=40 2>/dev/null
dd if=/dev/urandom of=/var/log/myapp/application.log.2 bs=1M count=30 2>/dev/null

# Fault 2: Old temp files that nobody cleaned up
for i in $(seq 1 20); do
    dd if=/dev/urandom of=/tmp/reports/report-2024-$(printf "%02d" $i).tmp bs=1M count=3 2>/dev/null
done

# Fault 3: Core dumps that have accumulated
dd if=/dev/urandom of=/var/cache/myapp/core.dump.1 bs=1M count=25 2>/dev/null
dd if=/dev/urandom of=/var/cache/myapp/core.dump.2 bs=1M count=25 2>/dev/null

# Fault 4: Start the fake app process, then delete its log file
# This creates a "deleted but held open" file that still consumes space
/opt/myapp/fake-app.sh &
sleep 1
# Write some data to it first
dd if=/dev/urandom of=/var/log/myapp/debug-old.log bs=1M count=20 2>/dev/null
# Now "delete" it — but the process still holds the fd open
rm /var/log/myapp/debug-old.log

echo "Disk space faults injected."
