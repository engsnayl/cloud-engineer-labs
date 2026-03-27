# Lab 14 — SSL Certificate Expired & Wrong File Paths

---

## Plain-English TLDR

You've been handed a ticket: the HTTPS dashboard is completely down. Nobody can reach it.

There are two things broken. First, the Nginx config file has been told to look for certificate files called `wrong-cert.crt` and `wrong-key.key` — but those files don't exist on disk. Second, the SSL directory is completely empty — there are no certificate files at all, valid or otherwise. Nothing to fall back on.

**The fix:** Generate a brand new certificate with a proper validity period, then correct the filenames in the Nginx config to point to it. Once both are sorted, Nginx starts and HTTPS comes back up.

---

## What Is This Lab Teaching You?

- How to diagnose an Nginx HTTPS outage from scratch
- How SSL certificates work and why they expire
- How to read and fix Nginx SSL configuration
- How to generate a self-signed certificate with OpenSSL
- How to verify a certificate's validity dates

---

## The Ticket

> **Incident:** HTTPS Dashboard Unreachable
> **Reported by:** Monitoring alert — port 443 health check failing
> **What we know:** The dashboard was working last week. It is now returning connection refused on port 443. Nginx status is unknown.

You're the engineer picking this up. You don't know what's broken yet. Let's find out.

---

## Step-by-Step Investigative Walkthrough

### Step 1 — Is Nginx actually running?

The first thing any engineer does when a web server is unreachable is check whether the service is even up. There's no point diagnosing certificates if the process isn't running.

```bash
service nginx status
```

**What you'll see:** Nginx is stopped — it's not running at all. This immediately rules out certificate negotiation as the *current* symptom. Something prevented Nginx from starting in the first place.

> **Why does this matter?** Nginx won't start if its configuration contains errors. SSL misconfiguration — including pointing to files that don't exist — causes Nginx to refuse to start entirely.

---

### Step 2 — Why won't Nginx start? Run the config test.

Nginx has a built-in tool for checking whether its configuration is valid before you try to start it. This is always the next move when the service is stopped unexpectedly.

```bash
nginx -t
```

| Part | What it does |
|------|-------------|
| `nginx` | The Nginx binary |
| `-t` | Test mode — validates config and exits without starting the server |

**What you'll see:** An error message like:
```
nginx: [emerg] cannot load certificate "/etc/nginx/ssl/wrong-cert.crt": BIO_new_file() failed
```

This tells you exactly what's wrong: Nginx is looking for a file called `wrong-cert.crt`, and it doesn't exist. The config has the wrong filename.

> **What does this mean in real life?** This error means someone edited the Nginx config (or the config was deployed incorrectly) with the wrong certificate filename. The actual cert on disk has a different name. Nginx is failing fast because it can't load what it needs.

---

### Step 3 — Find which config file references the missing certificate

The `nginx -t` error told you the filename Nginx is looking for (`wrong-cert.crt`), but it didn't tell you *which config file* referenced it. So the next move is to search for that string across the entire Nginx config directory:

```bash
grep -r "wrong-cert.crt" /etc/nginx/
```

| Part | What it does |
|------|-------------|
| `grep` | Search for a text pattern in files |
| `-r` | Recursive — search all files in the directory tree |
| `"wrong-cert.crt"` | The string to search for — taken directly from the error output |
| `/etc/nginx/` | The entire Nginx config directory |

**What you'll see:**
```
/etc/nginx/sites-enabled/dashboard-ssl:    ssl_certificate /etc/nginx/ssl/wrong-cert.crt;
```

That tells you exactly which file to open and confirms the directive causing the problem.

> **The general principle:** When a tool gives you a filename in an error message, search your config for that filename to find where it's being referenced. You're using the error output as a search term — this works for Nginx, Apache, and most other services.

**For reference — Nginx's standard directory layout:**

| Path | What it contains |
|------|-----------------|
| `/etc/nginx/nginx.conf` | Master config — pulls in everything else |
| `/etc/nginx/sites-available/` | All defined site configs (including disabled ones) |
| `/etc/nginx/sites-enabled/` | Symlinks to the configs that are actually active |
| `/etc/nginx/conf.d/` | Alternative drop-in config directory (used on some distros) |

Now open the config file:

```bash
cat /etc/nginx/sites-enabled/dashboard-ssl
```

| Part | What it does |
|------|-------------|
| `cat` | Print file contents to the terminal |
| `/etc/nginx/sites-enabled/dashboard-ssl` | The active site config for this HTTPS service |

**What to look for:** The `ssl_certificate` and `ssl_certificate_key` lines. They'll say something like:

```nginx
ssl_certificate     /etc/nginx/ssl/wrong-cert.crt;
ssl_certificate_key /etc/nginx/ssl/wrong-key.key;
```

Make a note of both the directory path (`/etc/nginx/ssl/`) and the filenames being referenced. You'll need both in the next step.

---

### Step 4 — Check what certificate files actually exist

You know the config is pointing to `/etc/nginx/ssl/`. Before generating anything, check whether any certificate files already exist in that directory — maybe there's something usable under a different name.

```bash
ls -la /etc/nginx/ssl/
```

| Part | What it does |
|------|-------------|
| `ls` | List directory contents |
| `-l` | Long format — shows permissions, owner, size, date |
| `-a` | Show all files including hidden ones |
| `/etc/nginx/ssl/` | The SSL directory referenced in the config |

**What you'll see:**
```
total 12
drwxr-xr-x 2 root root 4096 ...  .
drwxr-xr-x 1 root root 4096 ...  ..
```

The directory is completely empty. No certificate files at all — not the wrong-named ones, not alternatives, nothing.

> **What does this tell us?** There's nothing to inspect or salvage. We need to generate a certificate from scratch, then fix the config to point to it.

---

### Step 5 — Generate a new self-signed certificate

We'll create both the certificate and private key, giving them sensible standard names (`server.crt` and `server.key`). We'll then update the config to match these names in the next step.

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/CN=dashboard.internal"
```

| Part | What it does |
|------|-------------|
| `openssl req` | OpenSSL certificate request tool |
| `-x509` | Output a self-signed certificate instead of a signing request |
| `-nodes` | Don't encrypt the private key with a passphrase (Nginx needs to read it automatically on startup) |
| `-days 365` | Certificate is valid for 365 days from now |
| `-newkey rsa:2048` | Generate a new 2048-bit RSA key pair alongside the certificate |
| `-keyout /etc/nginx/ssl/server.key` | Write the private key to this path |
| `-out /etc/nginx/ssl/server.crt` | Write the certificate to this path |
| `-subj "/CN=dashboard.internal"` | Set the Common Name to match the server hostname (skips the interactive prompts) |

> **Why `-nodes`?** Without this flag, OpenSSL encrypts the private key with a passphrase. That means Nginx would ask you to type the passphrase every time it starts — including after an automated restart or server reboot. For any server process, you always want an unencrypted key so the service can start unattended.

---

### Step 6 — Fix the Nginx config to use the correct filenames

Now that we have a valid certificate at `server.crt`, we need to fix the two lines in the Nginx config that are pointing to the wrong filenames.

```bash
sed -i 's|ssl_certificate /etc/nginx/ssl/wrong-cert.crt;|ssl_certificate /etc/nginx/ssl/server.crt;|' /etc/nginx/sites-enabled/dashboard-ssl

sed -i 's|ssl_certificate_key /etc/nginx/ssl/wrong-key.key;|ssl_certificate_key /etc/nginx/ssl/server.key;|' /etc/nginx/sites-enabled/dashboard-ssl
```

| Part | What it does |
|------|-------------|
| `sed` | Stream editor — finds and replaces text in files |
| `-i` | Edit the file in-place (modifies the file directly, not just stdout) |
| `'s|old|new|'` | Substitution: replace `old` with `new` |
| `\|` delimiter | We use `\|` instead of the usual `/` because the strings contain forward slashes (file paths) — using `/` would confuse sed |

Alternatively, you can open the file directly in `vi` and edit it manually:

```bash
vi /etc/nginx/sites-enabled/dashboard-ssl
```

Either approach works. The `sed` route is faster if you're confident in the exact strings; `vi` is safer if you want to see the file before changing it.

---

### Step 7 — Validate the config before starting

Always run `nginx -t` before starting or reloading. This catches any remaining errors without taking the service down.

```bash
nginx -t
```

**What you should see:**
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

If you see errors, read them carefully — they tell you the file and line number of the problem.

---

### Step 8 — Start Nginx

```bash
service nginx start
```

| Part | What it does |
|------|-------------|
| `service` | The service management command |
| `nginx` | The service name |
| `start` | Start the service |

> **Lab vs production note:** In this lab environment we use `service nginx start`. On a production server with systemd, you'd use `systemctl start nginx` and `systemctl enable nginx` (to make it start automatically on boot).

---

### Step 9 — Verify HTTPS is responding

```bash
curl -sk https://localhost:443
```

| Part | What it does |
|------|-------------|
| `curl` | Command-line HTTP/HTTPS client |
| `-s` | Silent mode — suppresses progress output |
| `-k` | Skip certificate validation (required for self-signed certs — without this, curl refuses to connect) |
| `https://localhost:443` | The HTTPS endpoint to test |

**What you should see:** The dashboard HTML page. HTTPS is working.

---

### Step 10 — Confirm the new certificate's validity dates

One final check — confirm the certificate we just generated has a proper validity window.

```bash
openssl x509 -in /etc/nginx/ssl/server.crt -noout -dates
```

**What you should see:**
```
notBefore=<today's date>
notAfter=<date 365 days from now>
```

---

## Cleanup and Reset

To reset the lab back to its broken starting state so you can run through it again:

```bash
# Stop Nginx
service nginx stop

# Remove any certificate files you generated
rm -f /etc/nginx/ssl/server.crt /etc/nginx/ssl/server.key

# Restore the wrong filenames in the Nginx config
sed -i 's|ssl_certificate /etc/nginx/ssl/server.crt;|ssl_certificate /etc/nginx/ssl/wrong-cert.crt;|' /etc/nginx/sites-enabled/dashboard-ssl
sed -i 's|ssl_certificate_key /etc/nginx/ssl/server.key;|ssl_certificate_key /etc/nginx/ssl/wrong-key.key;|' /etc/nginx/sites-enabled/dashboard-ssl

echo "Lab reset. SSL directory is empty, config has wrong filenames. Run through from Step 1."
```

---

## Lab vs Production Notes

| Scenario | Lab approach | Production approach |
|----------|-------------|---------------------|
| Certificate type | Self-signed (`openssl req -x509`) | CA-signed (Let's Encrypt, DigiCert, AWS ACM) |
| Certificate renewal | Manual regeneration | Automated via `certbot --nginx` or ACM auto-renewal |
| Expiry monitoring | None | Prometheus ssl_exporter, Datadog, or cron + `openssl x509 -checkend` |
| Starting Nginx | `service nginx start` | `systemctl start nginx` + `systemctl enable nginx` |
| Private key permissions | Lab defaults | `chmod 600 server.key`, owned by root |
| Key storage | On disk | Secrets manager (AWS Secrets Manager, Vault) |

---

## Key Concepts

**SSL/TLS certificates have expiry dates.** Expired certificates are one of the most common causes of production HTTPS outages — monitoring expiry is critical.

**`openssl x509 -noout -dates` is your fastest diagnostic tool** for checking whether a certificate is valid.

**Nginx won't start if it can't find its certificate files.** A wrong path in the config is fatal at startup, not just at connection time.

**Self-signed certificates work for testing** but browsers will show a security warning. Production services require certificates from a trusted Certificate Authority.

**`-k` in curl skips cert validation** — useful for testing, never acceptable in production client code.

**`-nodes` means no passphrase on the private key** — required for Nginx to start without human input.

---

## Common Mistakes

- **Fixing the config paths but not regenerating the certificate** — correct paths + expired cert = HTTPS still broken for clients
- **Forgetting `-nodes` when generating the key** — Nginx will prompt for a passphrase on every start, breaking automated restarts
- **Using `-days 0`** — the cert expires instantly; always use a sensible validity period with monitoring in place
- **Not running `nginx -t` before `service nginx start`** — always validate before starting; a broken config brings the whole service down
- **Mismatched Common Name** — the CN in the certificate should match the hostname clients use, otherwise browsers show additional warnings
