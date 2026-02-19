#!/bin/bash
# Simulates an application that writes to a log file
# This process holds a file descriptor open even if the file is "deleted"
LOG_FILE="/var/log/myapp/debug-old.log"

# Write to the file and keep the fd open
exec 3>> "$LOG_FILE"
while true; do
    echo "$(date) [DEBUG] Processing transaction batch... heartbeat check ok" >&3
    sleep 60
done
