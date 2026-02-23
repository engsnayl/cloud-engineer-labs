#!/bin/bash
# =============================================================================
# Fault Injection: Systemd Crash Loop
# Creates a broken systemd service that crash-loops
# =============================================================================

# Create the actual application
cat > /opt/api-gateway.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 3000), H).serve_forever()
PYEOF

# Create a systemd unit file with multiple issues
cat > /etc/systemd/system/api-gateway.service << 'EOF'
[Unit]
Description=API Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/api-gatway.py
WorkingDirectory=/opt/api-gateway
User=apigateway
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
# Start it so it enters the crash loop
systemctl start api-gateway.service 2>/dev/null || true

echo "Systemd faults injected."
