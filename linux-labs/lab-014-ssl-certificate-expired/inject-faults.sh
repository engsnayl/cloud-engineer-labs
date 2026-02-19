#!/bin/bash
# =============================================================================
# Fault Injection: SSL Certificate Expired
# =============================================================================

mkdir -p /etc/nginx/ssl

# Fault 1: Create an already-expired certificate
openssl req -x509 -nodes -days 0 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/CN=dashboard.internal" 2>/dev/null

# Fault 2: Create an SSL Nginx config with wrong cert path
cat > /etc/nginx/sites-enabled/dashboard-ssl << 'EOF'
server {
    listen 443 ssl;
    server_name dashboard.internal;

    ssl_certificate /etc/nginx/ssl/wrong-cert.crt;
    ssl_certificate_key /etc/nginx/ssl/wrong-key.key;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# Create a dashboard page
echo '<!DOCTYPE html><html><body><h1>Dashboard OK</h1></body></html>' > /var/www/html/index.html

# Stop nginx
nginx -s stop 2>/dev/null || true
pkill nginx 2>/dev/null || true

echo "SSL certificate faults injected."
