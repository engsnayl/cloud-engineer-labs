# Solution Walkthrough — Proxy Headers and CORS

## The Problem

Nginx is acting as a reverse proxy in front of a backend API on port 3000, but it has **three issues** that break real-world web application functionality:

1. **No proxy headers are being forwarded** — when Nginx proxies a request to the backend, it's not passing along essential HTTP headers like `Host`, `X-Forwarded-For`, and `X-Real-IP`. This means the backend can't tell who the original client is, or what hostname they used. The backend sees "missing" for these headers.
2. **No CORS headers on responses** — CORS (Cross-Origin Resource Sharing) headers are required when a web page on one domain makes API requests to a different domain. Without these headers, browsers will block the API requests entirely. This is a very common problem when a frontend app (e.g., on `app.example.com`) needs to call an API (e.g., on `api.example.com`).
3. **OPTIONS pre-flight requests aren't handled** — before making certain cross-origin requests, browsers send an automatic OPTIONS request ("pre-flight check") to ask the server if the actual request is allowed. Without handling this, the browser never makes the real request.

## Thought Process

When an API works from `curl` but fails from a web browser, an experienced engineer immediately thinks about CORS:

1. **Check what the backend receives** — `curl -s http://localhost/api/` shows what the backend gets. If headers show "missing," the proxy isn't forwarding them.
2. **Check response headers** — `curl -sI http://localhost/api/` shows response headers. If there's no `Access-Control-Allow-Origin`, browsers will block cross-origin requests.
3. **Test OPTIONS requests** — `curl -X OPTIONS http://localhost/api/` simulates a pre-flight request. If the server returns an error or no CORS headers, the pre-flight fails and the browser blocks the real request.

The key insight: CORS is enforced by the browser, not the server. The API might be working perfectly, but if the response doesn't include the right CORS headers, the browser refuses to show the response to the JavaScript code.

## Step-by-Step Solution

### Step 1: Check the current behavior

```bash
curl -s http://localhost/api/
```

**What this does:** Makes a request through the Nginx proxy to the backend. The backend echoes back what headers it received. You'll see `Host:missing` and `XFF:missing` — confirming that Nginx is not forwarding the essential headers.

### Step 2: Check response headers for CORS

```bash
curl -sI http://localhost/api/
```

**What this does:** The `-I` flag requests only the HTTP headers (a HEAD request). You'll see there's no `Access-Control-Allow-Origin` header in the response, which means browsers would block any cross-origin JavaScript from using this API.

### Step 3: Test the OPTIONS pre-flight

```bash
curl -s -o /dev/null -w "%{http_code}" -X OPTIONS http://localhost/api/
```

**What this does:** Sends an OPTIONS request (simulating what a browser does before a cross-origin request). Without proper handling, this returns a 200 from the backend but without any CORS headers, or potentially a 405 (Method Not Allowed). Browsers need a successful OPTIONS response with CORS headers before they'll make the actual request.

### Step 4: Look at the current Nginx proxy config

```bash
cat /etc/nginx/sites-enabled/api-proxy
```

**What this does:** Shows the current configuration. You'll see a bare `proxy_pass` directive with no `proxy_set_header` directives (so headers aren't forwarded) and no `add_header` directives (so no CORS headers are added to responses).

### Step 5: Fix the Nginx proxy configuration

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

**What this does:** Rewrites the proxy configuration with three groups of additions:

**Proxy headers** (so the backend knows about the original client):
- `proxy_set_header Host $host` — passes the original hostname the client used (e.g., `api.example.com`)
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` — passes the client's real IP address. The `$proxy_add_x_forwarded_for` variable intelligently appends to any existing `X-Forwarded-For` header (important when there are multiple proxies in the chain)
- `proxy_set_header X-Real-IP $remote_addr` — another way to pass the client's IP address

**CORS headers** (so browsers allow cross-origin requests):
- `Access-Control-Allow-Origin *` — tells browsers that any domain can access this API. The `always` keyword ensures the header is included even on error responses.
- `Access-Control-Allow-Methods` — lists which HTTP methods are allowed for cross-origin requests
- `Access-Control-Allow-Headers` — lists which request headers are allowed (browsers block non-standard headers by default)

**OPTIONS handling** (so pre-flight checks succeed):
- `if ($request_method = OPTIONS) { return 204; }` — immediately returns a "204 No Content" for OPTIONS requests. The 204 status means "success, but no body to return," which is the standard response for pre-flight checks.

### Step 6: Test the configuration

```bash
nginx -t
```

**What this does:** Validates the config syntax before applying it.

### Step 7: Reload Nginx

```bash
nginx -s reload
```

**What this does:** Applies the new configuration without downtime.

### Step 8: Verify proxy headers are being forwarded

```bash
curl -s http://localhost/api/
```

**What this does:** The backend should now show it received the `Host` header (no longer "missing") and the proxy headers are flowing through correctly.

### Step 9: Verify CORS headers on responses

```bash
curl -sI http://localhost/api/
```

**What this does:** Check the response headers — you should now see `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods`, and `Access-Control-Allow-Headers` in the response.

### Step 10: Verify OPTIONS pre-flight works

```bash
curl -s -o /dev/null -w "%{http_code}" -X OPTIONS http://localhost/api/
```

**What this does:** The OPTIONS request should now return 204, confirming that pre-flight checks will pass.

## Docker Lab vs Real Life

- **CORS origin policy:** In this lab we use `Access-Control-Allow-Origin *` (allow everything). In production, you'd restrict this to specific domains: `Access-Control-Allow-Origin https://app.example.com`. Using `*` in production is a security risk because it allows any website to make API requests on behalf of your users.
- **CORS credentials:** If your API uses cookies or authentication, you also need `Access-Control-Allow-Credentials: true`, and you can't use `*` for the origin — you must specify the exact allowed domain.
- **Proxy protocol:** On cloud load balancers (ALB, CloudFront), the `X-Forwarded-For` header is automatically added. When using Nginx behind a cloud load balancer, you'd configure `set_real_ip_from` to trust the load balancer's IP and extract the real client IP correctly.
- **Backend handling:** In a real application, CORS can be handled at the application level (most web frameworks have CORS middleware) instead of at the Nginx level. The advantage of handling it in Nginx is that it applies consistently to all backends.
- **Pre-flight caching:** In production, you'd add `Access-Control-Max-Age: 86400` to tell browsers to cache the pre-flight response for 24 hours, reducing the number of OPTIONS requests.

## Key Concepts Learned

- **Reverse proxies strip headers by default** — you must explicitly configure `proxy_set_header` directives to forward client information to the backend
- **CORS is enforced by the browser, not the server** — the API itself might be working perfectly, but without CORS headers in the response, browsers block the JavaScript from accessing it
- **The three CORS essentials:** `Access-Control-Allow-Origin` (who can access), `Access-Control-Allow-Methods` (what methods), `Access-Control-Allow-Headers` (what headers)
- **OPTIONS pre-flight requests must be handled** — browsers send these automatically before certain cross-origin requests. If the server doesn't respond correctly, the real request never happens.
- **`X-Forwarded-For` preserves the original client IP** — without this, the backend sees the proxy's IP address instead of the actual client's IP

## Common Mistakes

- **Adding CORS headers but forgetting the `always` keyword** — without `always`, Nginx only adds headers on successful (2xx) responses. Error responses (4xx, 5xx) won't have CORS headers, and browsers will block them.
- **Using `Access-Control-Allow-Origin *` with credentials** — if your API uses cookies or auth tokens, the `*` wildcard doesn't work. You must specify the exact origin.
- **Not handling OPTIONS requests** — the CORS headers on GET/POST responses are useless if the OPTIONS pre-flight fails, because the browser never makes the actual request.
- **Forgetting `proxy_set_header Host`** — without this, the backend receives the proxy's hostname (e.g., "127.0.0.1:3000") instead of the original hostname. This breaks applications that use the Host header for routing or generating URLs.
- **Testing only with `curl` and not a browser** — `curl` doesn't enforce CORS. Your API might work perfectly with `curl` but fail in browsers. Test CORS with actual browser requests or browser developer tools.
