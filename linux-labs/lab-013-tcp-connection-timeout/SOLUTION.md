# Solution Walkthrough — TCP Connection Timeout

## The Problem

An application is trying to connect to Redis (an in-memory database commonly used for caching and sessions), but every connection attempt times out. There are **two issues** working together to cause this:

1. **`/etc/hosts` points `redis-server` to the wrong IP** — the hostname `redis-server` resolves to `10.0.0.99`, which is an unreachable address. The application tries to connect there, gets no response, and eventually times out. Redis is actually running on the local machine (`127.0.0.1`).
2. **Redis is listening on the wrong port** — Redis was started on port `6380`, but the application expects it on the standard Redis port `6379`. Even after fixing the hostname, the connection would fail because nothing is listening on 6379.

This is a classic "two-layer" networking problem: name resolution sends traffic to the wrong host, and even if you fix that, the port mismatch means the connection still fails.

## Thought Process

When a TCP connection times out, an experienced engineer works through the connection path systematically:

1. **Is the remote service even running?** Check with `ps aux | grep redis` or `pgrep redis-server`.
2. **What port is it listening on?** Use `ss -tlnp` to see all listening ports. If the service is on the wrong port, that's your answer.
3. **Does the hostname resolve correctly?** Use `getent hosts redis-server` to check where the hostname points. If it resolves to an unreachable IP, connections will hang and eventually time out.
4. **Test the connection directly** — `nc -zv redis-server 6379` tests TCP connectivity. A timeout means either the IP is wrong, the port is wrong, or a firewall is blocking it.

The key diagnostic difference: a **connection refused** error means the IP is reachable but nothing is listening on that port. A **timeout** means the IP is unreachable (wrong IP, firewall, network issue). Timeouts always point to a routing or host resolution problem.

## Step-by-Step Solution

### Step 1: Check if Redis is running

```bash
pgrep -a redis-server
```

**What this does:** Searches for any running Redis process and shows its full command line. The `-a` flag displays the arguments. You'll see Redis is running — so the service itself is fine. The problem is connecting to it.

### Step 2: Check what port Redis is actually listening on

```bash
ss -tlnp | grep redis
```

**What this does:** Shows TCP listening sockets filtered to Redis. You'll see Redis is bound to port `6380`, not the standard `6379`. The flags: `-t` for TCP, `-l` for listening, `-n` for numeric ports, `-p` for process info.

### Step 3: Check hostname resolution

```bash
getent hosts redis-server
```

**What this does:** Shows what IP address `redis-server` resolves to through the system's normal resolution chain (including `/etc/hosts`). You'll see it points to `10.0.0.99` — an incorrect, unreachable address. The correct address should be `127.0.0.1` (localhost), since Redis is running on this machine.

### Step 4: Fix the /etc/hosts entry

```bash
sed -i '/redis-server/d' /etc/hosts
echo "127.0.0.1  redis-server" >> /etc/hosts
```

**What this does:** First, deletes any existing line containing `redis-server` from `/etc/hosts`. Then adds the correct entry mapping `redis-server` to `127.0.0.1` (localhost). The `sed -i '/pattern/d'` syntax means "delete lines matching this pattern in-place."

### Step 5: Verify the hostname now resolves correctly

```bash
getent hosts redis-server
```

**What this does:** Confirms that `redis-server` now resolves to `127.0.0.1`.

### Step 6: Restart Redis on the correct port

```bash
redis-cli -p 6380 shutdown
redis-server --port 6379 --daemonize yes
```

**What this does:** First, we gracefully shut down the Redis instance running on port 6380. The `redis-cli -p 6380 shutdown` command connects to Redis on port 6380 and tells it to save its data and exit. Then we start a new Redis instance on the correct port 6379. The `--daemonize yes` flag makes Redis run in the background.

### Step 7: Verify Redis is now on the correct port

```bash
ss -tlnp | grep redis
```

**What this does:** Confirms Redis is now listening on port 6379 (not 6380).

### Step 8: Test the full connection

```bash
redis-cli -h redis-server -p 6379 ping
```

**What this does:** Connects to Redis using the hostname `redis-server` on port 6379 and sends a PING command. Redis should respond with "PONG." This tests the entire chain: hostname resolution resolves to the right IP, and Redis is listening on the expected port.

### Step 9: Test TCP connectivity

```bash
nc -zv redis-server 6379
```

**What this does:** Tests raw TCP connectivity to `redis-server` on port 6379. The `-z` flag means "just test the connection, don't send data" and `-v` means verbose. A successful message confirms that the full network path is working.

## Docker Lab vs Real Life

- **Redis configuration:** In this lab, we start Redis with command-line flags. In production, Redis configuration lives in `/etc/redis/redis.conf`, and you'd change the `port` directive there. You'd restart Redis with `systemctl restart redis` so the change persists.
- **Service discovery:** In production, hostnames like `redis-server` would typically be resolved through DNS (private DNS zones, service discovery tools like Consul, or Kubernetes Services), not `/etc/hosts` entries. `/etc/hosts` is fragile and doesn't scale.
- **Connection timeouts vs refused:** On a real network, a timeout usually means a firewall is silently dropping packets or the host is unreachable. A "connection refused" error means the host is reachable but nothing is listening. This distinction is critical for diagnosing network issues.
- **Redis persistence:** In this lab, shutting down and restarting Redis is quick and painless. In production, you'd need to consider data persistence (RDB snapshots, AOF logs) and whether clients need graceful handling during the restart.

## Key Concepts Learned

- **Connection timeouts mean the target is unreachable** — either the IP is wrong, the host is down, or a firewall is blocking. This is different from "connection refused," which means the host is reachable but no service is listening.
- **Always check both hostname resolution AND the listening port** — a working connection requires the right IP address AND the right port number
- **`ss -tlnp` is the go-to command for checking what's listening** — it's faster and more modern than `netstat`
- **`getent hosts` tests the full resolution chain** — unlike `dig` (which only queries DNS), `getent` checks `/etc/hosts` first, just like applications do
- **`nc -zv` is the quickest TCP connectivity test** — it tells you instantly whether a port is reachable, without needing the actual client software installed

## Common Mistakes

- **Only fixing one of the two issues** — fixing the hostname but leaving Redis on the wrong port (or vice versa) means the connection still fails. Both must be correct.
- **Testing with `ping` instead of a TCP connection test** — `ping` uses ICMP, which is a completely different protocol than TCP. A host can respond to ping but have no services listening. Always test the specific port with `nc -zv`, `redis-cli`, or `curl`.
- **Not shutting down the old Redis before starting a new one** — if you just start a new Redis on 6379 without stopping the one on 6380, you'll have two Redis instances running, which wastes memory and could cause confusion.
- **Confusing timeout vs. connection refused** — a timeout means packets are going into a void (wrong IP, firewall). Connection refused means the IP is right but nothing is listening on that port. The fix is different for each.
