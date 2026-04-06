# Solution Walkthrough: Part 3 — Frontend Layer

## What This Layer Does

The frontend tier is the **presentation layer** — it's what the user actually sees and interacts with. In our architecture, nginx plays two roles:

1. **Web server** — Serves the static HTML page to the browser
2. **Reverse proxy** — Forwards `/api/*` requests to the backend Flask service

## Files in This Layer

| File | Purpose |
|------|---------|
| `docker/frontend/index.html` | The webpage the user sees (HTML + CSS + JavaScript) |
| `docker/frontend/nginx.conf` | Nginx configuration — web server + reverse proxy rules |
| `docker/frontend/Dockerfile` | Container build instructions |
| `k8s/frontend-deployment.yaml` | Pod management for nginx |
| `k8s/frontend-service.yaml` | Internal load balancer for frontend pods |

## Nginx Configuration Explained

### The Reverse Proxy Pattern

```
  Browser makes request to: http://myapp.com/api/data
                              │
                              ▼
                     ┌─────────────────┐
                     │  nginx (port 80) │
                     │                  │
                     │  Sees "/api/" in │
                     │  the URL path    │
                     │        │         │
                     │        ▼         │
                     │  proxy_pass to   │
                     │  backend:5000    │
                     └────────┬─────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Flask (port 5000)│
                     │                  │
                     │  Handles the     │
                     │  request, queries│
                     │  the database    │
                     └──────────────────┘
```

The browser never talks to Flask directly. It sends ALL requests to nginx, and nginx decides where to route them. This has several benefits:

- **Single entry point** — One port (80) for everything
- **Same-origin** — The browser sees everything as coming from the same server, avoiding CORS issues
- **Flexibility** — You can swap the backend technology without the frontend knowing

### Location Block Priority

```nginx
location /api/ {
    proxy_pass http://backend:5000;
}

location / {
    root /usr/share/nginx/html;
    index index.html;
}
```

Nginx evaluates location blocks by **specificity**. `/api/` is more specific than `/`, so:
- `GET /api/health` → matches `/api/` → proxied to Flask
- `GET /api/data` → matches `/api/` → proxied to Flask
- `GET /` → matches `/` → serves index.html
- `GET /styles.css` → matches `/` → serves static file

### Proxy Headers — Why They Matter

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

Without these, the Flask backend would see every request as coming from nginx's internal IP address. These headers pass along the **real** client information:

| Header | What It Passes | Why It Matters |
|--------|---------------|----------------|
| `Host` | Original domain name | Backend can generate correct URLs |
| `X-Real-IP` | Client's actual IP | Logging, rate limiting, geo-location |
| `X-Forwarded-For` | Full proxy chain | Audit trail of all proxies involved |
| `X-Forwarded-Proto` | HTTP or HTTPS | Backend knows if request was encrypted |

## The HTML Page (index.html)

### Structure

The page is a single HTML file with embedded CSS and JavaScript. In a real project, these would be separate files, but bundling them makes this example self-contained.

The page has four sections:
1. **Header** — Title and live health status badge
2. **Architecture** — ASCII art diagram of the three-tier layout
3. **Items list** — Data fetched from the API, rendered dynamically
4. **Add form** — Input fields to create new items

### How the JavaScript Works

The JavaScript uses `fetch()` to make API calls. Here's the flow:

```
Page loads
  ├─► checkHealth() → fetch('/api/health') → updates status badge
  └─► loadItems()   → fetch('/api/data')   → renders item cards

User clicks "Add Item"
  └─► addItem()     → fetch('/api/data', POST) → refreshes list
```

All API calls go to **relative URLs** (`/api/health`, not `http://backend:5000/api/health`). This is important:
- The browser sends the request to the same host it loaded the page from (nginx)
- Nginx's reverse proxy forwards it to the backend
- If we used absolute URLs, we'd need to know the backend's address at build time, which defeats the purpose of the proxy

### The `async/await` Pattern

```javascript
async function checkHealth() {
    const response = await fetch('/api/health');
    const data = await response.json();
}
```

`fetch()` is **asynchronous** — it starts the HTTP request and returns a Promise (a placeholder for a future result). `await` pauses the function until the result arrives. Without `async/await`, you'd need nested callbacks, which are harder to read.

## The Dockerfile

The frontend Dockerfile is simpler than the backend's:

```dockerfile
FROM nginx:1.25-alpine    # Tiny base image (~40MB)
RUN rm /etc/nginx/conf.d/default.conf   # Remove default "Welcome" page
COPY nginx.conf /etc/nginx/nginx.conf   # Our custom config
COPY index.html /usr/share/nginx/html/  # Our webpage
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]      # Run in foreground
```

Key detail: `daemon off;` keeps nginx in the foreground. Docker containers exit when their main process exits. If nginx daemonized (ran in the background), the main process would finish immediately and the container would stop.

## The Kubernetes Manifests

### Why Different Resource Limits Than the Backend?

```yaml
resources:
  requests:
    memory: "64Mi"    # Backend: 128Mi
    cpu: "50m"        # Backend: 100m
```

Nginx is extremely efficient at serving static files. A single nginx process can handle thousands of requests per second with minimal memory. Flask, by comparison, runs Python code and database queries, which require more resources.

### Simpler Health Probes

```yaml
readinessProbe:
  httpGet:
    path: /          # Just check if nginx serves the page
    port: 80
  initialDelaySeconds: 3    # Nginx starts in ~1 second
```

The frontend probes are simpler than the backend's because:
- Nginx starts almost instantly (no interpreter to boot, no DB connection to establish)
- We just need to confirm it's serving the HTML page — no external dependencies to verify
- Shorter initial delay (3s vs 5s) because there's nothing to wait for

## Testing This Layer

```bash
# Port-forward to test the frontend directly
kubectl -n multi-tier-app port-forward svc/frontend 8080:80

# Open in browser: http://localhost:8080
# The page should load, but API calls will fail (no proxy target yet
# since port-forward bypasses nginx's proxy_pass)

# To test the full flow, use the Ingress (covered in SOLUTION-04)
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| "502 Bad Gateway" on `/api/*` calls | Backend Service not found | Verify backend pods are running in the same namespace |
| Page loads but shows "Backend: Unreachable" | API proxy not working | Check nginx.conf `proxy_pass` URL matches the backend Service name |
| Blank page | index.html not copied | Check Dockerfile COPY path matches |
| CSS looks broken | `mime.types` not included in nginx.conf | Ensure `include /etc/nginx/mime.types;` is in the http block |
