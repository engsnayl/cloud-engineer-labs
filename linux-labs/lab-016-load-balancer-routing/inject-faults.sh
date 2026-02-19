#!/bin/bash
# Start three backend "servers" on different ports
for port in 8001 8002 8003; do
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'Response from backend:$port')
    def log_message(self, format, *args): pass
HTTPServer(('127.0.0.1', $port), H).serve_forever()
" &
done
sleep 1

# Create broken Nginx LB config
cat > /etc/nginx/sites-enabled/loadbalancer << 'EOF'
upstream backends {
    # Fault 1: Only one backend listed (missing 8002 and 8003)
    server 127.0.0.1:8001;
    # Fault 2: These are commented out
    # server 127.0.0.1:8002;
    # server 127.0.0.1:8003;
}

server {
    listen 80;
    location / {
        proxy_pass http://backends;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
nginx 2>/dev/null || true

echo "Load balancer faults injected."
