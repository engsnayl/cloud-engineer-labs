#!/bin/bash
# =============================================================================
# Fault Injection: Log Rotation Broken
# Creates oversized logs with broken logrotate config
# =============================================================================

# Create app log directory and oversized logs
mkdir -p /var/log/app

# Create a big application log (use dd for speed)
dd if=/dev/urandom bs=1M count=80 2>/dev/null | base64 > /var/log/app/app.log
dd if=/dev/urandom bs=1M count=50 2>/dev/null | base64 > /var/log/app/access.log
dd if=/dev/urandom bs=1M count=30 2>/dev/null | base64 > /var/log/app/error.log

# Fault 1: Create a broken logrotate config (wrong path and syntax errors)
cat > /etc/logrotate.d/app << 'EOF'
/var/log/application/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
    # Missing closing brace - syntax error
EOF

# Fault 2: Wrong path in config (app vs application)
# The config points to /var/log/application/ but logs are in /var/log/app/

echo "Log rotation faults injected."
