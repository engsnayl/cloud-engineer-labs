from http.server import HTTPServer, BaseHTTPRequestHandler
from prometheus_client import Counter, Histogram, generate_latest
import random, time

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(generate_latest())
        elif self.path == '/':
            duration = random.uniform(0.01, 0.5)
            time.sleep(duration)
            REQUEST_COUNT.labels('GET', '/', '200').inc()
            REQUEST_DURATION.observe(duration)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'App OK')
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args): pass

print("App starting on :8080 with /metrics endpoint")
HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
