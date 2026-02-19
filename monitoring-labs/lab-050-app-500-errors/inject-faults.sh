#!/bin/bash
# Create an app that fails intermittently
cat > /opt/app.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import random, logging, sys, time

logging.basicConfig(stream=sys.stdout, level=logging.INFO, 
    format='%(asctime)s %(levelname)s %(message)s')

# Simulated database connection pool
DB_POOL = {"max": 5, "used": 0}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path
        
        if path == "/api/users":
            # This endpoint works fine
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"users": []}')
            logging.info(f"200 GET /api/users")
        
        elif path == "/api/payments":
            # FAULT: This endpoint fails when "DB pool exhausted"
            DB_POOL["used"] += 1
            if DB_POOL["used"] > DB_POOL["max"]:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b'{"error": "Internal Server Error"}')
                logging.error(f"500 GET /api/payments - DatabaseError: connection pool exhausted (used: {DB_POOL['used']}, max: {DB_POOL['max']})")
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"payments": []}')
                logging.info(f"200 GET /api/payments")
            # Slowly release connections
            if random.random() > 0.7:
                DB_POOL["used"] = max(0, DB_POOL["used"] - 1)
        
        elif path == "/api/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()
            logging.warning(f"404 GET {path}")
    
    def log_message(self, format, *args): pass

logging.info("Application starting on port 8080")
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
PYEOF

python3 /opt/app.py &
sleep 1

# Generate traffic to trigger the error pattern
for i in $(seq 1 50); do
    curl -s http://localhost:8080/api/payments > /dev/null &
    curl -s http://localhost:8080/api/users > /dev/null &
    sleep 0.1
done
wait

echo "Monitoring lab faults injected."
