# Solution Walkthrough — SSL Certificate Expired

## The Problem

An Nginx web server is supposed to serve a dashboard over HTTPS (port 443), but it's completely down because of **two SSL-related issues**:

1. **The SSL certificate is expired** — the certificate at `/etc/nginx/ssl/server.crt` was generated with `--days 0`, which means it expired immediately upon creation. Browsers and clients will reject expired certificates, and depending on the Nginx configuration, the server may refuse to start entirely.
2. **The Nginx SSL config points to wrong certificate filenames** — the site configuration references `wrong-cert.crt` and `wrong-key.key`, but the actual files are `server.crt` and `server.key`. Even if the certificate weren't expired, Nginx can't start because it can't find the files it's been told to use.

Nginx is completely stopped because it fails to load the (non-existent) certificate files when starting.

## Thought Process

When HTTPS isn't working, an experienced engineer checks the certificate chain:

1. **Is Nginx running?** If not, check why with `nginx -t` — configuration errors (including SSL file path problems) will prevent it from starting.
2. **Do the certificate files exist?** Check the paths referenced in the Nginx config against what's actually on disk.
3. **Is the certificate valid?** Use `openssl x509 -in cert.crt -noout -dates` to check the validity period. Expired certificates are one of the most common causes of HTTPS outages.
4. **Fix or regenerate** — if the cert is expired, you need a new one. For self-signed certs (like in a lab), you can generate one immediately. For production certs, you'd renew through your certificate authority.

## Step-by-Step Solution

### Step 1: Try to start Nginx and see the error

```bash
nginx -t
```

**What this does:** Tests the Nginx configuration for errors. You'll see an error about not being able to find `wrong-cert.crt` or `wrong-key.key`. This tells you the SSL file paths in the configuration are wrong.

### Step 2: Check the Nginx SSL configuration

```bash
cat /etc/nginx/sites-enabled/dashboard-ssl
```

**What this does:** Shows the site configuration file. Look at the `ssl_certificate` and `ssl_certificate_key` directives — they point to `wrong-cert.crt` and `wrong-key.key`.

### Step 3: Check what certificate files actually exist

```bash
ls -la /etc/nginx/ssl/
```

**What this does:** Lists the actual files in the SSL directory. You'll see `server.crt` and `server.key` — not the filenames the config references.

### Step 4: Check if the existing certificate is valid

```bash
openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates
```

**What this does:** Displays the "Not Before" (start date) and "Not After" (expiry date) of the certificate. The `-noout` flag suppresses the certificate body, and `-dates` shows just the validity period. You'll see the certificate has already expired (the "Not After" date is in the past or essentially right now).

### Step 5: Generate a new self-signed certificate

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/CN=dashboard.internal"
```

**What this does:** Creates a brand-new self-signed SSL certificate valid for 365 days. Here's what each option means:
- `req -x509` — generate a self-signed certificate (not a certificate signing request)
- `-nodes` — don't encrypt the private key with a passphrase (Nginx needs to read it without human interaction)
- `-days 365` — certificate is valid for one year
- `-newkey rsa:2048` — generate a new 2048-bit RSA private key
- `-keyout` — where to write the private key
- `-out` — where to write the certificate
- `-subj "/CN=dashboard.internal"` — set the Common Name to match the server name (avoids interactive prompts)

### Step 6: Fix the Nginx config to use the correct filenames

```bash
sed -i 's|ssl_certificate /etc/nginx/ssl/wrong-cert.crt;|ssl_certificate /etc/nginx/ssl/server.crt;|' /etc/nginx/sites-enabled/dashboard-ssl
sed -i 's|ssl_certificate_key /etc/nginx/ssl/wrong-key.key;|ssl_certificate_key /etc/nginx/ssl/server.key;|' /etc/nginx/sites-enabled/dashboard-ssl
```

**What this does:** Updates the two SSL directives to point to the correct filenames (`server.crt` and `server.key`). We use `|` as the sed delimiter instead of `/` because the replacement strings contain forward slashes.

### Step 7: Test the Nginx configuration

```bash
nginx -t
```

**What this does:** Validates the configuration. This time it should report "syntax is ok" and "test is successful" because the certificate files now exist at the paths specified in the config.

### Step 8: Start Nginx

```bash
service nginx start
```

**What this does:** Starts the Nginx web server. It will load the SSL certificate and begin serving HTTPS traffic on port 443.

### Step 9: Verify HTTPS is working

```bash
curl -sk https://localhost:443
```

**What this does:** Sends an HTTPS request to the local server. The `-s` flag silences progress output, and the `-k` flag tells curl to accept self-signed certificates (without `-k`, curl would reject our self-signed cert). You should see the dashboard HTML page.

### Step 10: Verify the new certificate's validity

```bash
openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates
```

**What this does:** Confirms the new certificate has a valid date range extending 365 days into the future.

## Docker Lab vs Real Life

- **Self-signed vs. CA-issued certificates:** In this lab we use a self-signed certificate, which is fine for internal tools and testing. In production, you'd use certificates from a trusted Certificate Authority (CA) like Let's Encrypt (free), DigiCert, or AWS Certificate Manager. Self-signed certs trigger browser warnings and aren't suitable for public-facing services.
- **Let's Encrypt automation:** In production, the standard approach is to use Let's Encrypt with `certbot` to automatically obtain and renew certificates. Certbot can even update Nginx config automatically: `certbot --nginx -d dashboard.example.com`.
- **Certificate monitoring:** In production, you'd monitor certificate expiry dates with tools like Prometheus (with the ssl_exporter), Datadog, or a simple cron job that checks `openssl x509 -checkend 2592000` (warns if expiring within 30 days). Certificate expiry is one of the most common causes of production outages.
- **Starting Nginx:** In this lab we use `service nginx start`. On a production server with systemd, you'd use `systemctl start nginx` and `systemctl enable nginx`.
- **Private key security:** In production, the private key file should have `600` permissions and be owned by root. The private key should never be shared, committed to version control, or transmitted over unencrypted channels.

## Key Concepts Learned

- **SSL/TLS certificates have expiry dates** — when a certificate expires, HTTPS stops working. This is one of the most common causes of production outages worldwide.
- **`openssl x509 -noout -dates` checks certificate validity** — this is the quickest way to see if a certificate is expired or about to expire
- **Nginx must be able to find its certificate files** — if the paths in the config don't match the actual file locations, Nginx won't start at all
- **Self-signed certificates work for testing** but trigger browser warnings. Production services need CA-signed certificates.
- **The `-k` flag in curl skips certificate validation** — useful for testing self-signed certs, but never ignore certificate errors in production client code

## Common Mistakes

- **Fixing the config paths but not regenerating the expired certificate** — even with correct paths, an expired certificate will cause problems for clients connecting to the server
- **Generating the certificate without matching the server_name** — the Common Name (CN) or Subject Alternative Name (SAN) should match the hostname clients use. Mismatches cause certificate warnings.
- **Forgetting `-nodes` when generating the key** — without this flag, OpenSSL encrypts the private key with a passphrase. Nginx would then prompt for the passphrase every time it starts, which breaks automated restarts.
- **Setting a very short validity period** — while `-days 365` is fine for a lab, in production you'd want monitoring in place to catch upcoming expirations well before they happen
- **Not testing with `nginx -t` before starting** — always validate the config first. A failed start can leave the server completely down with no HTTPS at all.
