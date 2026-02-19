#!/bin/bash
# =============================================================================
# Fault Injection: Firewall Blocking
# Introduces restrictive iptables rules that block app traffic
# =============================================================================

# Start a web application on port 8080
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'App OK')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
" &

# Start a health check endpoint on port 8081
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'Healthy')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 8081), H).serve_forever()
" &

sleep 1

# Fault: Apply overly restrictive iptables rules
# Allow established connections (so Docker exec still works)
iptables -F INPUT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -p tcp --dport 22 -j ACCEPT
# Deliberately missing: rules for 8080 and 8081
# Set default to DROP
iptables -P INPUT DROP

echo "Firewall faults injected."
