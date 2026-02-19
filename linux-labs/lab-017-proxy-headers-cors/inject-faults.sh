#!/bin/bash
# Start a backend API
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        host = self.headers.get('Host', 'missing')
        xff = self.headers.get('X-Forwarded-For', 'missing')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f'Host:{host} XFF:{xff}'.encode())
    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, format, *args): pass
HTTPServer(('127.0.0.1', 3000), H).serve_forever()
" &
sleep 1

# Create Nginx proxy with missing headers and no CORS
cat > /etc/nginx/sites-enabled/api-proxy << 'EOF'
server {
    listen 80;
    location /api/ {
        # Fault 1: No proxy headers passed
        proxy_pass http://127.0.0.1:3000/;
        # Missing: proxy_set_header Host, X-Forwarded-For, X-Real-IP
        
        # Fault 2: No CORS headers
        # Missing: Access-Control-Allow-Origin, Methods, Headers
        
        # Fault 3: OPTIONS method not handled
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
nginx 2>/dev/null || true

echo "Proxy header faults injected."
