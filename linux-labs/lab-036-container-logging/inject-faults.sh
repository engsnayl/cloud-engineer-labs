#!/bin/bash
# Create an app that logs to a file instead of stdout (the anti-pattern)
cat > /opt/app.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import logging

# Fault: Logging to a file instead of stdout
logging.basicConfig(filename='/var/log/app.log', level=logging.INFO)

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        logging.info(f"Request from {self.client_address[0]}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'App OK')
    def log_message(self, format, *args):
        logging.info(format % args)

logging.info("Application starting on port 8080")
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
PYEOF

python3 /opt/app.py &

# Generate some log entries
sleep 1
for i in $(seq 1 20); do
    curl -s http://localhost:8080 > /dev/null 2>&1
done

echo "Logging faults injected."
