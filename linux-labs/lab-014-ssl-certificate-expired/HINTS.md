# Hints — Lab 014: SSL Certificate Expired

## Hint 1 — Check the certificate
`openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates` shows when the cert was issued and when it expires.

## Hint 2 — Generate a new self-signed cert
`openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/server.key -out /etc/nginx/ssl/server.crt -subj "/CN=dashboard.internal"`

## Hint 3 — Fix the Nginx config
The SSL config in `/etc/nginx/sites-enabled/dashboard-ssl` points to wrong filenames. Update the paths to match your actual cert and key files.
