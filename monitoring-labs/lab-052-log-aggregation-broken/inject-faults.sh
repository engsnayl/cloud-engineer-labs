#!/bin/bash
# Start a fake log aggregation endpoint
python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('0.0.0.0', 5514))
f = open('/var/log/aggregated.log', 'a')
while True:
    data, addr = s.recvfrom(4096)
    f.write(data.decode() + '\n')
    f.flush()
" &

# Fault 1: Rsyslog config forwards to wrong port
cat > /etc/rsyslog.d/50-forwarding.conf << 'EOF'
# Forward all logs to central aggregation
*.* @127.0.0.1:5515
EOF
# Port should be 5514, not 5515

# Fault 2: Rsyslog not running
# (don't start it)

# Generate some application logs
cat > /opt/generate-logs.sh << 'SCRIPT'
#!/bin/bash
while true; do
    logger -t myapp "Processing request $(date +%s)"
    sleep 2
done
SCRIPT
chmod +x /opt/generate-logs.sh

echo "Log aggregation faults injected."
