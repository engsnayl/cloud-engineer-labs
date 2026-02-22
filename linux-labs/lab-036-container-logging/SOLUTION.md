# Solution Walkthrough — Container Logging

## The Problem

The application inside the container is logging to a **file** (`/var/log/app.log`) instead of to **stdout** (standard output). This is a fundamental anti-pattern in containerised environments because `docker logs` only captures output written to stdout and stderr. When logs go to a file inside the container:

1. **`docker logs` shows nothing** — the primary way operators monitor containers is completely blind
2. **Log files grow inside the container** — they eat up disk space in the container's writable layer
3. **Logs are lost when the container is removed** — files inside a container disappear when the container is deleted
4. **Centralised log collection doesn't work** — tools like Fluentd, Logstash, and CloudWatch Logs agent all rely on `docker logs` (which reads stdout/stderr). Logging to a file bypasses the entire log pipeline.

The Docker philosophy is: containers should write logs to stdout/stderr, and the platform handles collection, rotation, and shipping.

## Thought Process

When `docker logs` shows nothing for a running container, an experienced engineer immediately suspects the application is logging to a file:

1. **Check `docker logs`** — if it's empty but the app is running, the output is going somewhere else.
2. **Look inside the container for log files** — check common locations like `/var/log/`, `/tmp/`, or application-specific directories.
3. **Find the logging configuration** — look at the application code or config to see where it's sending logs.
4. **Fix the output destination** — change the application to log to stdout instead of a file. In Python, this means removing the `filename` parameter from `logging.basicConfig()`.

## Step-by-Step Solution

### Step 1: Check what docker logs shows

```bash
docker logs lab036-container-logging 2>&1 | tail -5
```

**What this does:** Tries to view the container's log output. You'll see it's empty or only shows the initial process startup (not the application's log messages). This is the symptom — the application's logs aren't reaching Docker's log driver.

### Step 2: Verify the app is actually running and generating activity

```bash
docker exec lab036-container-logging curl -s http://localhost:8080
```

**What this does:** Makes a request to the application to confirm it's running and processing requests. It responds with "App OK," proving the application works — it's just not logging to stdout.

### Step 3: Find where the logs are actually going

```bash
docker exec lab036-container-logging cat /var/log/app.log
```

**What this does:** Reads the log file inside the container. You'll see all the application log entries — access logs, request information, etc. This confirms the logs are being written to a file instead of stdout.

### Step 4: Look at the application code

```bash
docker exec lab036-container-logging cat /opt/app.py
```

**What this does:** Shows the Python application source code. You'll find the problem on the `logging.basicConfig()` line — it has `filename='/var/log/app.log'`, which directs all log output to that file instead of stdout.

### Step 5: Fix the application to log to stdout

```bash
docker exec lab036-container-logging bash -c "cat > /opt/app.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import logging
import sys

# Fixed: Log to stdout instead of a file
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        logging.info(f\"Request from {self.client_address[0]}\")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'App OK')
    def log_message(self, format, *args):
        logging.info(format % args)

logging.info(\"Application starting on port 8080\")
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
PYEOF"
```

**What this does:** Rewrites the application code with two key changes:
- Added `import sys` — needed to reference `sys.stdout`
- Changed `filename='/var/log/app.log'` to `stream=sys.stdout` — this tells Python's logging module to write to standard output instead of a file. Docker's log driver captures everything written to stdout.

### Step 6: Clean up the old log file

```bash
docker exec lab036-container-logging rm -f /var/log/app.log
```

**What this does:** Removes the old log file from inside the container. Since we've fixed the application to log to stdout, this file is no longer needed and just wastes space.

### Step 7: Restart the application

```bash
docker exec lab036-container-logging bash -c "pkill -f 'python3 /opt/app.py'; sleep 1; python3 /opt/app.py &"
```

**What this does:** Kills the old application process (still logging to a file) and starts the new version (logging to stdout). The `sleep 1` gives the old process time to fully exit before starting the new one.

### Step 8: Generate some traffic and verify docker logs works

```bash
docker exec lab036-container-logging curl -s http://localhost:8080 > /dev/null
docker logs lab036-container-logging 2>&1 | tail -5
```

**What this does:** Makes a request to generate a log entry, then checks `docker logs`. This time you should see the application's log messages — the starting message and the request log. `docker logs` is now capturing the application output because it's going to stdout.

## Docker Lab vs Real Life

- **Log drivers:** In this lab, Docker uses the default `json-file` log driver, which stores stdout/stderr as JSON files on the host. In production, you'd configure a log driver to ship logs directly to a centralized system: `--log-driver=awslogs` for CloudWatch, `--log-driver=fluentd` for Fluentd/EFK stack, or `--log-driver=gelf` for Graylog.
- **Log rotation:** Docker's default json-file driver doesn't rotate logs, so they grow forever. In production, configure rotation: `--log-opt max-size=10m --log-opt max-file=3` limits logs to 3 files of 10MB each.
- **Structured logging:** In production, you'd use structured logging (JSON format) rather than plain text. This makes logs searchable and parseable by centralized logging systems. Most Python apps use `python-json-logger` for this.
- **Twelve-Factor App methodology:** The logging approach in this lab follows the Twelve-Factor App principle (Factor XI): "Treat logs as event streams." Applications should never concern themselves with routing or storage of their output — they write to stdout, and the platform handles the rest.
- **Sidecar pattern:** In Kubernetes, if an application absolutely must write to a file, you can use a sidecar container that tails the file and writes it to stdout. But it's better to fix the application.

## Key Concepts Learned

- **Containers should log to stdout/stderr, never to files** — this is a fundamental container best practice. Docker, Kubernetes, and all container orchestrators are built around capturing stdout/stderr.
- **`docker logs` only captures stdout/stderr** — anything written to files inside the container is invisible to Docker's logging infrastructure.
- **Python's `logging.basicConfig(stream=sys.stdout)` logs to stdout** — removing the `filename` parameter and adding `stream=sys.stdout` redirects all log output to standard output.
- **Logs in files inside containers are ephemeral** — they disappear when the container is removed, making them useless for post-incident analysis.
- **Centralised logging depends on stdout** — tools like Fluentd, CloudWatch, and EFK stack all consume logs from Docker's log driver, which only captures stdout/stderr.

## Common Mistakes

- **Leaving the old log file in place** — the old `/var/log/app.log` continues to take up space. Remove it after fixing the application.
- **Using `print()` instead of the `logging` module** — while `print()` does write to stdout (and would appear in `docker logs`), proper logging with the `logging` module provides timestamps, log levels, and structured output. Always use the logging module.
- **Not restarting the application after changing the code** — the running process is still using the old code in memory. You must restart it for changes to take effect.
- **Redirecting to a file and then tailing it** — some people try to keep the file and use `tail -f` to pipe it to stdout. This adds complexity for no benefit. Just log to stdout directly.
- **Not configuring Docker log rotation** — even with stdout logging, Docker's default json-file driver stores logs on the host without rotation. In production, always set `max-size` and `max-file` options.
