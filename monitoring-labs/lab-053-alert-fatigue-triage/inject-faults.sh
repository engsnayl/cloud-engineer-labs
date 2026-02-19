#!/bin/bash
# Create a simulated alert config with too many noisy alerts
mkdir -p /opt/monitoring

cat > /opt/monitoring/alerts.json << 'EOF'
{
  "alerts": [
    {"name": "cpu_above_1_percent", "threshold": 1, "severity": "critical", "description": "CPU usage above 1%"},
    {"name": "memory_above_10_percent", "threshold": 10, "severity": "critical", "description": "Memory above 10%"},
    {"name": "disk_above_50_percent", "threshold": 50, "severity": "critical", "description": "Disk above 50%"},
    {"name": "http_5xx_any", "threshold": 1, "severity": "critical", "description": "Any 5xx error"},
    {"name": "response_time_above_10ms", "threshold": 10, "severity": "critical", "description": "Response time above 10ms"},
    {"name": "container_restart", "threshold": 1, "severity": "critical", "description": "Any container restart"},
    {"name": "ssl_cert_expiry_365d", "threshold": 365, "severity": "critical", "description": "SSL cert expires within 365 days"},
    {"name": "log_error_any", "threshold": 1, "severity": "critical", "description": "Any ERROR in logs"},
    {"name": "network_packet_loss_any", "threshold": 0.01, "severity": "critical", "description": "Any packet loss > 0.01%"},
    {"name": "pod_pending_1s", "threshold": 1, "severity": "critical", "description": "Pod pending for 1 second"}
  ]
}
EOF

# Create a simulated alert log showing the noise
cat > /opt/monitoring/alert-log.txt << 'EOF'
2024-01-15 08:00:01 CRITICAL cpu_above_1_percent - CPU at 3% on web-01
2024-01-15 08:00:01 CRITICAL memory_above_10_percent - Memory at 45% on web-01
2024-01-15 08:00:01 CRITICAL response_time_above_10ms - Response 42ms on /api/users
2024-01-15 08:00:02 CRITICAL disk_above_50_percent - Disk at 62% on db-01
2024-01-15 08:00:03 CRITICAL http_5xx_any - 1 error on /api/payments (500)
2024-01-15 08:00:05 CRITICAL container_restart - web-worker-3 restarted (OOM)
2024-01-15 08:00:10 CRITICAL log_error_any - ERROR: Failed to send analytics event
2024-01-15 08:00:15 CRITICAL ssl_cert_expiry_365d - cert expires in 340 days
2024-01-15 08:01:01 CRITICAL cpu_above_1_percent - CPU at 5% on web-02
2024-01-15 08:01:01 CRITICAL memory_above_10_percent - Memory at 38% on web-02
... (repeats 200+ times per day)
EOF

# Task: Create a fixed alerts config at /opt/monitoring/alerts-fixed.json
# with proper thresholds and severity levels

echo "Alert fatigue lab set up."
echo "Review /opt/monitoring/alerts.json and /opt/monitoring/alert-log.txt"
echo "Create /opt/monitoring/alerts-fixed.json with proper thresholds."
