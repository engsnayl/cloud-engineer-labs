from http.server import HTTPServer, BaseHTTPRequestHandler
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import random, time, threading

REQUEST_COUNT = Counter('http_requests_total', 'Total requests', ['method', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'Request duration')
ACTIVE_CONNECTIONS = Gauge('active_connections', 'Active connections')

def simulate_traffic():
    while True:
        ACTIVE_CONNECTIONS.set(random.randint(5, 50))
        REQUEST_COUNT.labels('GET', '200').inc(random.randint(1, 10))
        REQUEST_COUNT.labels('GET', '500').inc(random.randint(0, 1))
        REQUEST_DURATION.observe(random.uniform(0.01, 2.0))
        time.sleep(1)

threading.Thread(target=simulate_traffic, daemon=True).start()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(generate_latest())
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
    def log_message(self, format, *args): pass

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
