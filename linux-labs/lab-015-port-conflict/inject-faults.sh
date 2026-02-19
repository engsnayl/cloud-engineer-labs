#!/bin/bash
# =============================================================================
# Fault Injection: Port Conflict
# =============================================================================

# Create the actual API service
cat > /opt/api.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'API OK')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
PYEOF

# Fault: Start a rogue process on port 8080 first
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(503)
        self.end_headers()
        self.wfile.write(b'Stale process')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
" &

echo "Port conflict faults injected."
