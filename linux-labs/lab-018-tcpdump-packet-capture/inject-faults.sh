#!/bin/bash
# Start a legitimate web server
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')
    def log_message(self, format, *args): pass
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
" &

# Fault: Start a rogue process making suspicious outbound connections
python3 -c "
import socket, time
while True:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        s.connect(('127.0.0.1', 9999))
        s.send(b'EXFIL DATA PACKET')
        s.close()
    except: pass
    time.sleep(3)
" &

# Start a listener on 9999 to accept the connections
python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 9999))
s.listen(5)
while True:
    conn, addr = s.accept()
    data = conn.recv(1024)
    conn.close()
" &

echo "Packet capture faults injected."
