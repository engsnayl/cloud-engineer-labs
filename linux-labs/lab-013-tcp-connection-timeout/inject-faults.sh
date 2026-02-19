#!/bin/bash
# =============================================================================
# Fault Injection: TCP Connection Timeout
# =============================================================================

# Start Redis on a non-standard port (but config still says 6379)
redis-server --port 6380 --daemonize yes

# Fault 1: /etc/hosts points redis-server to wrong IP
echo "10.0.0.99  redis-server" >> /etc/hosts

# Fault 2: Redis is on port 6380 but app expects 6379

echo "TCP connection faults injected."
