#!/bin/bash
# =============================================================================
# Fault Injection: Nginx Down
# Introduces multiple realistic faults that prevent Nginx from starting
# =============================================================================

# Fault 1: Break the nginx.conf with a syntax error (missing semicolon)
# This is the most common real-world Nginx issue
sed -i 's/worker_connections 768;/worker_connections 768/' /etc/nginx/nginx.conf

# Fault 2: Wrong permissions on the log directory
# Nginx can't write logs if permissions are wrong
chmod 000 /var/log/nginx

# Fault 3: Put a conflicting listen directive in a site config
# Simulates a previous engineer's botched config change
cat > /etc/nginx/sites-enabled/broken-site << 'EOF'
server {
    listen 80;
    server_name portal.internal;
    root /var/www/nonexistent;

    location / {
        proxy_pass http://localhost:9999;
    }
}
EOF

# Make sure nginx is stopped
nginx -s stop 2>/dev/null || true
pkill nginx 2>/dev/null || true

echo "Faults injected. Nginx is down."
