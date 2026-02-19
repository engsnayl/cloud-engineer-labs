#!/bin/bash
mkdir -p /var/log/app /var/log/infra

# Create simulated logs from multiple services telling a story
cat > /var/log/infra/system.log << 'EOF'
2024-01-15 01:45:00 INFO  disk-monitor: /data partition at 78% usage
2024-01-15 01:55:00 WARN  disk-monitor: /data partition at 85% usage
2024-01-15 02:00:00 ERROR disk-monitor: /data partition at 95% usage - CRITICAL
2024-01-15 02:00:15 ERROR postgres: FATAL: could not write to file "pg_wal/000000010000000000000042": No space left on device
2024-01-15 02:00:16 ERROR postgres: database system is shut down
2024-01-15 02:00:30 WARN  systemd: postgresql.service: Main process exited, code=exited, status=1/FAILURE
2024-01-15 02:00:31 INFO  systemd: postgresql.service: Scheduled restart job
2024-01-15 02:00:35 ERROR postgres: FATAL: could not write to file - No space left on device
2024-01-15 02:01:00 ERROR systemd: postgresql.service: Start request repeated too quickly, refusing to start
EOF

cat > /var/log/app/payment-api.log << 'EOF'
2024-01-15 01:59:55 INFO  payment-api: Processing payment PAY-98234 amount=150.00
2024-01-15 02:00:01 INFO  payment-api: Processing payment PAY-98235 amount=75.50
2024-01-15 02:00:18 ERROR payment-api: Database connection failed: connection refused to 10.0.1.50:5432
2024-01-15 02:00:19 ERROR payment-api: Retry 1/3 for database connection
2024-01-15 02:00:25 ERROR payment-api: Retry 2/3 for database connection
2024-01-15 02:00:31 ERROR payment-api: Retry 3/3 for database connection
2024-01-15 02:00:32 ERROR payment-api: All retries exhausted. Returning 503 to clients
2024-01-15 02:00:32 ERROR payment-api: Health check failing - database unavailable
2024-01-15 02:05:00 WARN  payment-api: 157 failed requests in last 5 minutes
2024-01-15 02:10:00 WARN  payment-api: 312 failed requests in last 5 minutes
2024-01-15 02:30:00 WARN  payment-api: Circuit breaker OPEN for database operations
EOF

cat > /var/log/app/notification-service.log << 'EOF'
2024-01-15 02:10:00 WARN  notification: High error rate alert triggered for payment-api
2024-01-15 02:10:01 INFO  notification: Sending PagerDuty alert to on-call
2024-01-15 02:10:02 ERROR notification: PagerDuty API returned 429 - rate limited
2024-01-15 02:10:05 INFO  notification: Retry sending PagerDuty alert
2024-01-15 02:10:06 INFO  notification: PagerDuty alert sent successfully
2024-01-15 02:25:00 INFO  notification: On-call engineer acknowledged alert
EOF

cat > /var/log/infra/resolution.log << 'EOF'
2024-01-15 02:30:00 INFO  engineer: Investigating disk usage on db-server
2024-01-15 02:35:00 INFO  engineer: Found: pg_wal directory consuming 45GB. Old WAL files not being cleaned up
2024-01-15 02:40:00 INFO  engineer: Running pg_archivecleanup to remove old WAL files
2024-01-15 02:45:00 INFO  disk-monitor: /data partition at 52% usage
2024-01-15 02:50:00 INFO  engineer: Starting postgresql service
2024-01-15 02:50:05 INFO  postgres: database system is ready to accept connections
2024-01-15 02:50:10 INFO  payment-api: Database connection restored
2024-01-15 02:50:15 INFO  payment-api: Health check passing
2024-01-15 02:55:00 INFO  payment-api: Circuit breaker CLOSED - normal operations resumed
2024-01-15 03:00:00 INFO  engineer: Monitoring - all systems nominal
2024-01-15 04:30:00 INFO  engineer: Incident resolved. Setting up WAL archival cron job to prevent recurrence
EOF

# Task: Create /tmp/post-incident-report.txt with:
# - Timeline of events
# - Root cause
# - Impact (duration, affected services, failed requests)
# - Resolution steps
# - Action items to prevent recurrence

echo "Post-incident lab set up."
echo "Review logs in /var/log/app/ and /var/log/infra/"
echo "Create /tmp/post-incident-report.txt"
