# Lab 017 — Proxy Headers and CORS
## Solution Walkthrough

---

## TLDR — What's Actually Going On Here (Plain English)

You have Nginx sitting in front of a backend API. Think of Nginx as a receptionist — requests come in through the front door, Nginx passes them on to the backend, and then sends the response back.

The problem is: **this receptionist is a bit useless in three specific ways.**

1. **It's not telling the backend who actually walked in the door.** When a client makes a request, Nginx is supposed to pass along details like the client's real IP address and the hostname they used. Right now it's stripping those out. The backend has no idea where the request originally came from.

2. **It's not telling browsers that they're allowed to talk to this API from other websites.** Browsers have a built-in security rule: if your webpage is on `app.example.com` and it tries to call an API on `api.example.com`, the browser will refuse to show the response unless the server explicitly says "that's fine." This is CORS. Without CORS headers in the response, browsers block the request entirely — even if the API is working perfectly.

3. **It's ignoring the browser's pre-flight check.** Before a browser makes a real cross-origin request, it first sends a quick "are you okay with this?" check called an OPTIONS request. If the server doesn't respond to that correctly, the browser never even sends the real request.

**The fix:** Add three groups of directives to the Nginx proxy config — proxy forwarding headers, CORS response headers, and OPTIONS pre-flight handling.

---

## Background: Key Concepts

### What is a Reverse Proxy?
Nginx sits in front of your backend application. Clients talk to Nginx (port 80), and Nginx forwards requests to the backend (port 3000). The client never directly talks to the backend. This is extremely common in production — it allows you to add SSL, load balancing, caching, and security rules in one place.

### What is CORS?
CORS (Cross-Origin Resource Sharing) is a browser security mechanism. It exists to prevent malicious websites from silently making API requests on behalf of logged-in users. If your frontend is on `app.example.com` and calls `api.example.com`, the browser checks whether the API's response includes `Access-Control-Allow-Origin`. If it doesn't, the browser refuses to give the JavaScript access to the response — even though the request went through and the API responded fine. **CORS is enforced by the browser, not the server.**

### What is an OPTIONS Pre-flight?
For certain cross-origin requests (anything that isn't a simple GET/POST with basic headers), browsers first send a "pre-flight" OPTIONS request asking: "Is this kind of request allowed?" The server must respond to this with CORS headers before the browser will send the real request.

### What are Proxy Headers?
When Nginx forwards a request to a backend, by default it doesn't include the original client's IP or hostname — the backend just sees the proxy's IP. The `X-Forwarded-For` and `X-Real-IP` headers are a standard convention for carrying the original client information through a proxy chain.

---

## The Ticket

> **Reported issue:** The backend API is reachable via `curl` but frontend JavaScript calls are being blocked by the browser. Additionally, the backend team is reporting that they can't see the correct client IP addresses in their logs — everything shows up as the proxy IP.

You've been handed this ticket cold. You don't know what's broken yet. Here's how you work through it.

---

## Step-by-Step Investigative Walkthrough

> **Note:** All commands in this lab are run from **inside the container**. Both Nginx and the backend are running inside it, so the full traffic flow (curl → Nginx → backend) happens within the container environment.
>
> ```bash
> docker exec -it lab017-proxy-headers-cors bash
> ```

---

### Step 1 — First, understand what we're working with

Before touching any config, get your bearings. What's running, and what does the traffic flow look like?

```bash
curl -s http://localhost/api/
```

| Part | What it does |
|------|-------------|
| `curl` | Command-line HTTP client — makes HTTP requests from the terminal |
| `-s` | Silent mode — suppresses progress output so you just see the response body |
| `http://localhost/api/` | The URL to request — hitting port 80 on this machine (Nginx), which proxies through to the backend on port 3000 |

**Expected output (before fix):**
```
Host:127.0.0.1:3000 XFF:missing
```

The backend echoes back the headers it received. `Host:127.0.0.1:3000` is Nginx's upstream address — the backend is seeing the proxy's address, not the original client's hostname. `XFF:missing` confirms `X-Forwarded-For` isn't being forwarded at all.

> **The "how would I know this?" question:** You know because the backend is literally telling you. This is why echoing received headers in a health/debug endpoint is a common debugging technique — the backend can't lie about what it received.

---

### Step 2 — Check what the response headers look like

The ticket mentions browser JavaScript calls being blocked. Your immediate instinct should be: CORS.

```bash
curl -si http://localhost/api/
```

| Part | What it does |
|------|-------------|
| `curl` | Command-line HTTP client |
| `-s` | Silent mode |
| `-i` | Include the response headers in the output — sends a normal GET request but prints headers too |
| `http://localhost/api/` | The endpoint to inspect |

> **Note:** You might reach for `-I` (uppercase) here — that sends a HEAD request instead of GET. This backend returns a 501 for HEAD requests, so use lowercase `-i` instead. Same information, normal GET request.

**Expected output (before fix):**
```
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
Date: ...
Transfer-Encoding: chunked
Connection: keep-alive
Host:127.0.0.1:3000 XFF:missing
```

**What you're looking for:** Scan for anything starting with `Access-Control-`. You'll find nothing. No `Access-Control-Allow-Origin` header — which means browsers will block any cross-origin JavaScript from accessing this API.

> **The "how would I know this?" question:** `curl` doesn't enforce CORS — only browsers do. But you can diagnose CORS problems from the terminal by checking whether the server is sending the right headers. If there's no `Access-Control-Allow-Origin` in the response, the browser will block JavaScript from accessing it.

---

### Step 3 — Simulate what a browser does before every cross-origin request

Browsers don't just fire the real request straight away. For cross-origin requests, they first send an OPTIONS request ("pre-flight") to check if the server will allow the real request. Let's simulate that.

```bash
curl -sv -X OPTIONS http://localhost/api/ 2>&1 | head -30
```

| Part | What it does |
|------|-------------|
| `curl` | Command-line HTTP client |
| `-s` | Silent mode — suppresses progress meter |
| `-v` | Verbose — shows the full request and response including all headers |
| `-X OPTIONS` | Override the HTTP method — use OPTIONS instead of the default GET |
| `2>&1` | Redirect stderr to stdout — curl's verbose output goes to stderr by default, this merges it so you can see everything |
| `\| head -30` | Only show the first 30 lines — stops the output flooding the terminal |
| `http://localhost/api/` | The endpoint to test |

**Expected output (before fix):**
```
* Trying 127.0.0.1:80...
* Connected to localhost (127.0.0.1) port 80 (#0)
> OPTIONS /api/ HTTP/1.1
> Host: localhost
...
< HTTP/1.1 200 OK
< Server: nginx/1.18.0 (Ubuntu)
< Transfer-Encoding: chunked
< Connection: keep-alive
```

**What you're looking for:** The backend returns 200, but there are no `Access-Control-Allow-*` headers in the response. A browser seeing this would refuse to send the real request — the pre-flight responded but without the CORS headers the browser needs to proceed.

> **Useful to know — checking just the status code:**
> ```bash
> curl -s -o /dev/null -w "%{http_code}\n" -X OPTIONS http://localhost/api/
> ```
> `-o /dev/null` throws away the body, `-w "%{http_code}\n"` prints just the status code. Handy in scripts where you only need a pass/fail number.

> **The "how would I know this?" question:** You know to test OPTIONS because you know how CORS works — browsers always send a pre-flight before certain cross-origin requests. If you want to know whether the pre-flight will succeed, you simulate it yourself.

---

### Step 4 — Look at the actual Nginx config to find out why

You've now confirmed three symptoms from the outside. Now go look at the config to understand the root cause.

```bash
cat /etc/nginx/sites-enabled/api-proxy
```

| Part | What it does |
|------|-------------|
| `cat` | Print the contents of a file to the terminal |
| `/etc/nginx/sites-enabled/api-proxy` | The Nginx virtual host config for this proxy. `sites-enabled` contains configs that are active — the convention in Debian/Ubuntu-based Nginx setups |

**What you're looking for:** A bare `proxy_pass` directive with no `proxy_set_header` directives and no `add_header` directives. That explains everything:

- No `proxy_set_header` → no headers forwarded to backend
- No `add_header` → no CORS headers on responses
- No `if ($request_method = OPTIONS)` block → OPTIONS pre-flights get no special treatment

> **The "how would I know this?" question:** You know to look in `/etc/nginx/sites-enabled/` because that's the standard Nginx location for active virtual host configs. When something is proxying wrongly, the proxy config is the first place you look. The symptoms you've already confirmed guide you to exactly what to look for in the file.

---

### Step 5 — Fix the Nginx configuration

Now you know what's missing, add it. You need three groups of additions:

```bash
cat > /etc/nginx/sites-enabled/api-proxy << 'EOF'
server {
    listen 80;
    location /api/ {
        # Proxy headers — pass client information to the backend
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;

        # CORS headers — allow cross-origin requests
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;

        # Handle OPTIONS pre-flight requests
        if ($request_method = OPTIONS) {
            return 204;
        }

        proxy_pass http://127.0.0.1:3000/;
    }
}
EOF
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `cat >` | Write to a file — `cat` reads from stdin, `>` redirects the output to the file (overwriting it) |
| `/etc/nginx/sites-enabled/api-proxy` | The destination file — the active Nginx config we're replacing |
| `<< 'EOF'` | "Here document" — everything typed until the line with just `EOF` is treated as the input. The single quotes around `'EOF'` prevent the shell from expanding `$variables` inside the block, which would break Nginx variables like `$host` |
| `EOF` (at the end) | Signals the end of the here document input |

**Directive breakdown — the three groups you're adding:**

**Group 1: Proxy headers** (so the backend knows who the original client was)

| Directive | What it does |
|-----------|-------------|
| `proxy_set_header Host $host` | Passes the original hostname the client used. Without this, the backend sees the proxy's upstream address instead |
| `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` | Passes the client's real IP. The variable `$proxy_add_x_forwarded_for` appends to any existing `X-Forwarded-For` header rather than overwriting it — important when multiple proxies are chained |
| `proxy_set_header X-Real-IP $remote_addr` | Another way to carry the client's IP — single value, no chaining |

**Group 2: CORS headers** (so browsers allow cross-origin JavaScript access)

| Directive | What it does |
|-----------|-------------|
| `add_header Access-Control-Allow-Origin * always` | Tells browsers any origin can access this API. The `always` keyword ensures the header is added even on error responses (4xx/5xx) — without it, browser JS can't read error responses either |
| `add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always` | Lists the HTTP methods a cross-origin request is allowed to use |
| `add_header Access-Control-Allow-Headers "Content-Type, Authorization" always` | Lists which request headers cross-origin requests are allowed to send |

**Group 3: OPTIONS pre-flight handling**

| Directive | What it does |
|-----------|-------------|
| `if ($request_method = OPTIONS)` | Checks whether the incoming request is an OPTIONS request |
| `return 204` | Returns "204 No Content" — the standard correct response for a pre-flight check. The CORS headers added above will be included in this response |

---

### Step 6 — Validate the config before applying it

Never reload Nginx without testing the config first. A syntax error will take the server down.

```bash
nginx -t
```

| Part | What it does |
|------|-------------|
| `nginx` | The Nginx binary |
| `-t` | Test mode — parses and validates all config files and reports syntax errors without actually applying anything |

**Expected output:**
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

---

### Step 7 — Reload Nginx to apply the fix

```bash
nginx -s reload
```

| Part | What it does |
|------|-------------|
| `nginx` | The Nginx binary |
| `-s reload` | Sends a "reload" signal to the running Nginx master process. It re-reads the config and gracefully restarts workers — no downtime, no dropped connections |

> **Why `-s reload` instead of a full restart?** A restart drops all active connections instantly. A reload lets in-flight requests finish while new workers pick up the new config. In production, always reload.

---

### Step 8 — Verify the proxy headers are now flowing through

```bash
curl -s http://localhost/api/
```

**Expected output (after fix):**
```
Host:localhost XFF:127.0.0.1
```

The backend now sees the original hostname and client IP — no longer the proxy's upstream address.

---

### Step 9 — Verify the CORS headers appear in responses

```bash
curl -si http://localhost/api/
```

**Expected output (after fix):**
```
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
...
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Host:localhost XFF:127.0.0.1
```

All three CORS headers are now present. A browser would allow JavaScript to access responses from this API.

---

### Step 10 — Verify OPTIONS pre-flight now returns 204

```bash
curl -sv -X OPTIONS http://localhost/api/ 2>&1 | head -30
```

**Expected output (after fix):**
```
* Trying 127.0.0.1:80...
* Connected to localhost (127.0.0.1) port 80 (#0)
> OPTIONS /api/ HTTP/1.1
> Host: localhost
...
< HTTP/1.1 204 No Content
< Server: nginx/1.18.0 (Ubuntu)
< Connection: keep-alive
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Methods: GET, POST, OPTIONS
< Access-Control-Allow-Headers: Content-Type, Authorization
```

204 with all three CORS headers — a browser hitting this endpoint would now pass the pre-flight and send the real request.

---

## Before / After

### Before (broken config)
```nginx
server {
    listen 80;
    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
    }
}
```

### After (fixed config)
```nginx
server {
    listen 80;
    location /api/ {
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;

        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;

        if ($request_method = OPTIONS) {
            return 204;
        }

        proxy_pass http://127.0.0.1:3000/;
    }
}
```

---

## Cleanup / Reset (to re-run the lab from Step 1)

```bash
git checkout -- /etc/nginx/sites-enabled/api-proxy
nginx -s reload
```

This reverts the Nginx config back to the broken version committed in the repo and reloads it.

---

## Docker Lab vs Real Life

| This Lab | Production Reality |
|----------|-------------------|
| `Access-Control-Allow-Origin *` (allow all) | Restrict to specific domains: `Access-Control-Allow-Origin https://app.example.com`. Wildcard in production is a security risk |
| No credentials | If your API uses cookies or auth tokens, you also need `Access-Control-Allow-Credentials: true` — and you **cannot** use `*` for the origin, must be an exact domain |
| Single proxy | On AWS behind an ALB or CloudFront, `X-Forwarded-For` is set automatically by the load balancer. You'd configure `set_real_ip_from` in Nginx to trust the LB IP and extract the real client IP |
| CORS in Nginx | Most web frameworks have CORS middleware you can handle at the application level instead. Nginx-level CORS applies consistently across all backends |
| No pre-flight caching | In production, add `Access-Control-Max-Age: 86400` to tell browsers to cache the pre-flight result for 24 hours, reducing unnecessary OPTIONS requests |

---

## Common Mistakes

- **Forgetting `always` on `add_header`** — without it, CORS headers only appear on 2xx responses. Error responses (4xx, 5xx) won't have them, and browser JavaScript can't read those errors either.
- **Using `Access-Control-Allow-Origin *` with credentials** — the `*` wildcard doesn't work if your API uses cookies or auth headers. You must specify the exact origin.
- **CORS headers but no OPTIONS handling** — if the pre-flight OPTIONS request fails, the browser never sends the real request. CORS headers on GET/POST responses are useless without a working OPTIONS response.
- **Forgetting `proxy_set_header Host`** — the backend receives the proxy's upstream address instead of the real hostname. Breaks any application that uses the Host header for routing or URL generation.
- **Testing only with `curl` and declaring it fixed** — `curl` ignores CORS entirely. Always verify with the actual response headers, and test from a real browser if possible.
