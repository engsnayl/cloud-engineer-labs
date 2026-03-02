# Solution Walkthrough — Lab 026: Container Logging

---

## TLDR — The Problem & Fix in Plain English

The app inside this container is writing its logs to a file (`/var/log/app.log`) instead of printing them to the screen (stdout). Docker can only see what a container prints to the screen. So when you run `docker logs` you get nothing — the logs are trapped in a file inside the container that nobody can see from outside.

**The fix is two lines in the Python code:**

1. Add `import sys` (loads Python's system module so we can reference stdout)
2. Change `filename='/var/log/app.log'` to `stream=sys.stdout` (tells the app to print to screen instead of writing to a file)

Then restart the container. `docker logs` will now show the application output.

---

## How Container Logging Should Work

In a properly configured container environment, logs flow through a simple pipeline:

```
App writes to stdout/stderr
       ↓
Docker captures that output (because it's watching stdout/stderr of PID 1)
       ↓
Docker stores it via a log driver (default: json-file on the host)
       ↓
"docker logs" reads from the log driver and shows you the output
       ↓
In production: a log shipper (Fluentd, CloudWatch agent, etc.) picks up the logs
       ↓
Logs arrive in a centralised system (CloudWatch, ELK, Datadog, etc.)
```

**When an app logs to a FILE instead of stdout, it breaks this entire chain at step 1.** Docker never sees the output, so everything downstream gets nothing.

---

## What Is an Anti-Pattern?

An anti-pattern is something that seems like a sensible approach but actually causes problems. Logging to a file feels natural — that's how traditional servers work. But in containers, it's the wrong approach because containers are temporary, disposable, and rely on stdout for their entire logging infrastructure. The "right" pattern is: app prints to stdout, platform handles everything else.

---

## What Is stdout?

In Linux, every running process automatically gets three standard streams. These aren't files sitting on disk — they're channels the operating system provides to every process:

- **stdout** (standard output) — where normal output goes. File descriptor 1.
- **stderr** (standard error) — where error messages go. File descriptor 2.
- **stdin** (standard input) — where input comes from. File descriptor 0.

When you run `echo hello` in a terminal, that text goes to stdout, which your terminal displays on screen. Docker hooks into this same mechanism — it captures whatever a container's main process (PID 1) writes to stdout and stderr. That's what `docker logs` shows you.

---

## The Problem

The application inside the container is logging to a file (`/var/log/app.log`) instead of to stdout. This causes four problems:

1. **`docker logs` shows nothing** — the primary way operators monitor containers is completely blind
2. **Log files grow inside the container** — eating up disk space in the container's writable layer
3. **Logs are lost when the container is removed** — files inside a container disappear when it's deleted
4. **Centralised log collection doesn't work** — tools like Fluentd, CloudWatch, and ELK all rely on `docker logs`, which reads stdout/stderr. Logging to a file bypasses the entire pipeline

---

## Thought Process

When `docker logs` shows nothing for a running container, an experienced engineer immediately suspects the app is logging to a file:

1. Check `docker logs` — if it's empty but the app is running, output is going somewhere else
2. Look inside the container for log files — check common locations like `/var/log/`, `/tmp/`, or app-specific directories
3. Find the logging configuration — look at the application code to see where it's sending logs
4. Fix the output destination — change the application to log to stdout instead of a file

---

## Step-by-Step Solution

### Step 1: Check what docker logs shows

```bash
docker logs lab026-container-logging 2>&1 | tail -5
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker logs` | Ask Docker to show you what this container has printed to stdout/stderr |
| `lab026-container-logging` | The name of the container |
| `2>&1` | Merge stderr (stream 2) into stdout (stream 1) so we see everything |
| `\|` | Pipe — send the output of the left command into the right command |
| `tail -5` | Show only the last 5 lines |

You'll see it's empty or only shows the setup message — not the application's actual log messages. This confirms the symptom: logs aren't reaching Docker.

---

### Step 2: Verify the app is running

```bash
docker exec lab026-container-logging curl -s http://localhost:8080
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker exec` | Run a command INSIDE the container (you're on the host/Pi, but this reaches into the container) |
| `lab026-container-logging` | Which container to reach into |
| `curl` | A tool for making HTTP requests |
| `-s` | Silent mode — don't show progress bars |
| `http://localhost:8080` | The app's address INSIDE the container |

You'll get `App OK` back. The app is running and serving traffic — it's just not logging to stdout.

> **Key Distinction: `docker exec` vs host commands**
>
> `docker exec` means "reach inside the container and run this command." The path `/var/log/app.log` in a `docker exec` command refers to a file INSIDE the container, not on your Pi.
>
> `docker logs` and `docker ps` are commands you run on the host that talk to the Docker daemon. They don't go inside the container.

---

### Step 3: Find where the logs are actually going

```bash
docker exec lab026-container-logging cat /var/log/app.log
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker exec` | Run a command inside the container |
| `cat` | Print the contents of a file |
| `/var/log/app.log` | The log file INSIDE the container (not on your Pi) |

You'll see all the application log entries — request logs, timestamps, etc. This confirms the logs ARE being generated, they're just going to a file instead of stdout.

---

### Step 4: Look at the application code

```bash
docker exec lab026-container-logging cat /opt/app.py
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker exec` | Run a command inside the container |
| `cat /opt/app.py` | Print the Python application source code |

You'll find the problem on the `logging.basicConfig()` line:

```python
logging.basicConfig(filename='/var/log/app.log', level=logging.INFO)
```

The `filename=` parameter is telling Python's logging module to write everything to that file instead of stdout.

---

### Step 5: Fix the application to log to stdout

Edit `/opt/app.py` inside the container (using `vi` or `nano` via `docker exec -it lab026-container-logging vi /opt/app.py`). The fix is two lines:

**Line 1 — Add the import:**

Add this line at the top with the other imports:

```python
import sys
```

`sys` is a Python module that gives access to system-level things. We need it to reference `sys.stdout`. Without this import, Python wouldn't know what `sys.stdout` means.

**Line 2 — Change the logging destination:**

Change:

```python
logging.basicConfig(filename='/var/log/app.log', level=logging.INFO)
```

To:

```python
logging.basicConfig(stream=sys.stdout, level=logging.INFO)
```

This tells the logging module: "send output to stdout instead of that file." Docker is watching stdout, so it will now capture everything.

**The fixed file should look like this:**

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import logging
import sys

logging.basicConfig(stream=sys.stdout, level=logging.INFO)

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        logging.info(f"Request from {self.client_address[0]}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'App OK')
    def log_message(self, format, *args):
        logging.info(format % args)

logging.info("Application starting on port 8080")
HTTPServer(('0.0.0.0', 8080), H).serve_forever()
```

> **Real-World Context: Would I Write This Python Code?**
>
> As a Cloud/DevOps Engineer, probably not. In practice you would:
>
> 1. **Diagnose the problem** — "the app logs to a file, it needs to log to stdout"
> 2. **Raise it with the dev team** — "your `logging.basicConfig()` has `filename=`, it needs `stream=sys.stdout`"
> 3. **Maybe submit a small PR yourself** if it's a quick fix like this
>
> The value of this lab isn't making you a Python developer. It's making sure you can spot the anti-pattern, explain why it's broken, and articulate the fix.

---

### Step 6: Clean up the old log file

```bash
docker exec lab026-container-logging rm -f /var/log/app.log
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker exec` | Run a command inside the container |
| `rm` | Remove (delete) a file |
| `-f` | Force — don't complain if the file doesn't exist |
| `/var/log/app.log` | The old log file we no longer need |

---

### Step 7: Restart the container

```bash
docker restart lab026-container-logging
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker restart` | Stop and start the container — the app relaunches with the updated code |
| `lab026-container-logging` | The container name |

This works because the container's entrypoint runs the Python app as its main process (PID 1). When the container restarts, it launches the updated `app.py`, and since PID 1's stdout is what Docker watches, the logs will now be captured.

---

### Step 8: Generate traffic and verify docker logs works

```bash
docker exec lab026-container-logging curl -s http://localhost:8080 > /dev/null
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker exec ... curl -s http://localhost:8080` | Make a request to generate a log entry |
| `> /dev/null` | Throw away the response (we only care about the log it generates) |

```bash
docker logs lab026-container-logging 2>&1 | tail -5
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `docker logs` | Show what the container has printed to stdout/stderr |
| `2>&1` | Merge stderr into stdout |
| `\| tail -5` | Show the last 5 lines |

This time you should see actual application log messages — the startup message and request logs. `docker logs` is now capturing the application output because it's going to stdout.

---

## Docker Lab vs Real Life

**Log drivers:** In this lab, Docker uses the default `json-file` log driver, which stores stdout/stderr as JSON files on the host. In production, you'd configure a log driver to ship logs directly to a centralised system: `--log-driver=awslogs` for CloudWatch, `--log-driver=fluentd` for Fluentd/EFK, or `--log-driver=gelf` for Graylog.

**Log rotation:** Docker's default json-file driver doesn't rotate logs, so they grow forever. In production, configure rotation: `--log-opt max-size=10m --log-opt max-file=3` limits logs to 3 files of 10MB each.

**Structured logging:** In production, you'd use structured logging (JSON format) rather than plain text. This makes logs searchable and parseable by centralised logging systems.

**Twelve-Factor App:** This lab follows the Twelve-Factor App principle (Factor XI): "Treat logs as event streams." Applications should never concern themselves with routing or storage of their output — they write to stdout, and the platform handles the rest.

**Sidecar pattern (Kubernetes):** In Kubernetes, if an app absolutely must write to a file, you can use a sidecar container that tails the file and writes it to stdout. But it's always better to fix the application.

**In production you'd never patch a running container:** In this lab we edited a file inside a running container. In the real world, you'd fix the code in the repository, rebuild the Docker image, and redeploy. Containers are disposable — you replace them, you don't repair them.

---

## Key Concepts Learned

- **Containers should log to stdout/stderr, never to files** — Docker, Kubernetes, and all container orchestrators are built around capturing stdout/stderr.
- **`docker logs` only captures stdout/stderr** — anything written to files inside the container is invisible to Docker's logging infrastructure.
- **Python's `logging.basicConfig(stream=sys.stdout)` logs to stdout** — removing the `filename` parameter and adding `stream=sys.stdout` redirects all log output to standard output.
- **Logs in files inside containers are ephemeral** — they disappear when the container is removed, making them useless for post-incident analysis.
- **Centralised logging depends on stdout** — Fluentd, CloudWatch, and ELK all consume logs from Docker's log driver, which only captures stdout/stderr.
- **`docker exec` runs commands INSIDE the container** — file paths in `docker exec` commands refer to the container's filesystem, not your host machine.

---

## Common Mistakes

- **Leaving the old log file in place** — the old `/var/log/app.log` continues to take up space. Remove it after fixing the application.
- **Using `print()` instead of the logging module** — while `print()` writes to stdout, proper logging provides timestamps, log levels, and structured output.
- **Not restarting after changing the code** — the running process uses the old code in memory. You must restart for changes to take effect.
- **Not configuring Docker log rotation** — even with stdout logging, Docker's default json-file driver stores logs on the host without rotation. Always set `max-size` and `max-file` in production.
