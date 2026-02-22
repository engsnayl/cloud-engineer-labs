# Solution Walkthrough — Load Balancer Routing

## The Problem

Nginx is configured as a reverse proxy/load balancer in front of three backend application servers (running on ports 8001, 8002, and 8003), but it's only sending traffic to **one** backend. The other two backends are running fine but never receive any requests. Here's what's wrong:

The Nginx `upstream` configuration block only has one backend listed — the entries for backends on ports 8002 and 8003 are **commented out**. This means all traffic goes to a single server, defeating the entire purpose of having a load balancer. If that one backend goes down, the entire application goes down. With proper load balancing, the other two backends would continue serving traffic.

## Thought Process

When a load balancer isn't distributing traffic correctly, an experienced engineer checks:

1. **Are all backends running?** Use `ss -tlnp` to verify that all three backend ports (8001, 8002, 8003) are listening. If some backends are down, that's a different problem.
2. **What does the Nginx config say?** Look at the `upstream` block to see which backends are configured. If backends are missing or commented out, traffic can't reach them.
3. **Test distribution** — make several requests and check if responses come from different backends. Nginx uses round-robin by default, so you should see responses cycling through all configured backends.

The core insight here is that a load balancer can only distribute traffic to backends it knows about. If the configuration only lists one backend, you effectively don't have load balancing at all — just a proxy.

## Step-by-Step Solution

### Step 1: Verify all backend servers are running

```bash
ss -tlnp | grep -E '800[1-3]'
```

**What this does:** Checks if processes are listening on ports 8001, 8002, and 8003. You should see all three backends running. The `-E` flag enables extended regular expressions, and `800[1-3]` matches 8001, 8002, or 8003.

### Step 2: Test the current load balancer behavior

```bash
for i in 1 2 3 4 5 6; do curl -s http://localhost; echo; done
```

**What this does:** Makes 6 requests to the load balancer and prints each response. You'll see every response comes from "backend:8001" — no traffic reaches 8002 or 8003. This confirms the load balancer is only using one backend.

### Step 3: Look at the current Nginx upstream config

```bash
cat /etc/nginx/sites-enabled/loadbalancer
```

**What this does:** Shows the Nginx load balancer configuration. In the `upstream backends` block, you'll see that only `server 127.0.0.1:8001` is active — the entries for 8002 and 8003 are commented out with `#` symbols.

### Step 4: Fix the upstream config by uncommenting the missing backends

```bash
sed -i 's|# server 127.0.0.1:8002;|    server 127.0.0.1:8002;|' /etc/nginx/sites-enabled/loadbalancer
sed -i 's|# server 127.0.0.1:8003;|    server 127.0.0.1:8003;|' /etc/nginx/sites-enabled/loadbalancer
```

**What this does:** Uncomments the two disabled backend entries by removing the `#` characters. After this, the upstream block will have all three backends listed, and Nginx will distribute traffic across all of them.

### Step 5: Test the configuration

```bash
nginx -t
```

**What this does:** Validates the Nginx configuration for syntax errors. Always run this before applying changes — a syntax error could take down the load balancer entirely.

### Step 6: Reload Nginx to apply the changes

```bash
nginx -s reload
```

**What this does:** Tells the running Nginx process to reload its configuration without stopping. The `-s reload` signal is graceful — Nginx finishes handling any in-progress requests before applying the new config. This avoids any downtime, unlike `nginx -s stop && nginx` which would briefly drop all connections.

### Step 7: Verify traffic is now distributed

```bash
for i in 1 2 3 4 5 6; do curl -s http://localhost; echo; done
```

**What this does:** Makes 6 requests again. This time you should see responses from different backends — "backend:8001", "backend:8002", and "backend:8003" appearing in a round-robin pattern. Nginx distributes requests evenly across all configured backends by default.

## Docker Lab vs Real Life

- **Nginx reload vs restart:** In this lab we use `nginx -s reload`, which is the correct approach in production too. A reload applies config changes without dropping existing connections. On a systemd server, `systemctl reload nginx` does the same thing.
- **Backend health checks:** In this lab, all backends are healthy. In production, you'd add health checking so Nginx automatically removes unhealthy backends. Nginx Plus (the paid version) has built-in active health checks. The open-source version only does passive health checks (marking backends as down after failed requests).
- **Load balancing algorithms:** This lab uses the default `round-robin` algorithm. In production, you might use `least_conn` (send to the backend with fewest connections), `ip_hash` (same client always goes to the same backend, useful for sessions), or `random with two choices`.
- **Cloud load balancers:** In production cloud environments, you'd often use a managed load balancer (AWS ALB/NLB, GCP Load Balancer, Azure Load Balancer) rather than running Nginx yourself. These handle scaling, health checks, and SSL termination automatically.
- **Service discovery:** Instead of hardcoding backend IPs in the config, production systems use service discovery (Consul, Kubernetes Services, AWS ECS service discovery) to dynamically register and deregister backends.

## Key Concepts Learned

- **A load balancer only balances across backends it knows about** — if backends are missing from the configuration, they won't receive any traffic
- **Nginx uses round-robin by default** — requests are distributed evenly across all configured backends in the upstream block
- **`nginx -s reload` applies changes without downtime** — always prefer reload over stop/start for configuration changes
- **Always test with `nginx -t` before reloading** — a bad config applied with `nginx -s reload` can take down the entire load balancer
- **Multiple backend servers provide redundancy** — if one backend goes down, the others continue serving traffic. With only one backend, you have no redundancy at all.

## Common Mistakes

- **Using `nginx -s stop` then `nginx`** — this causes a brief outage where no requests are served. Use `nginx -s reload` for zero-downtime configuration changes.
- **Not verifying all backends are running** — if you uncomment the backend entries but one of the backend processes isn't actually running, Nginx will get errors when routing traffic to it. Always verify backends are up first.
- **Editing the wrong config file** — Nginx may have multiple config files in `sites-enabled`. Make sure you're editing the load balancer config, not a default site or another virtual host.
- **Not testing with enough requests** — making a single request won't prove load balancing works. Make at least N+1 requests (where N is the number of backends) to see the round-robin pattern.
- **Forgetting that commented-out lines are invisible to Nginx** — a `#` at the beginning of a line means Nginx completely ignores it. The backends might as well not exist.
