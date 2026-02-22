# Solution Walkthrough — Systemd Crash Loop

## The Problem

A systemd service called `api-gateway.service` is stuck in a crash loop — it keeps starting, immediately failing, and restarting over and over. Systemd is doing exactly what it's configured to do (`Restart=always`), but the service itself can never successfully start because of **three issues** in the unit file:

1. **Typo in the ExecStart path** — the unit file says `/opt/api-gatway.py` (missing the "e" in "gateway"). The actual file is `/opt/api-gateway.py`. The process starts, Python can't find the file, and it exits with an error.
2. **WorkingDirectory doesn't exist** — the unit file specifies `WorkingDirectory=/opt/api-gateway`, but that directory was never created. Systemd won't even attempt to start the process if the working directory doesn't exist.
3. **The specified User doesn't exist** — the unit file says `User=apigateway`, but no such user exists on the system. Systemd can't switch to a non-existent user, so the service fails immediately.

With `Restart=always` and `RestartSec=1`, systemd tries to restart the service every second, creating a rapid crash loop that fills the journal with errors.

## Thought Process

When a systemd service is crash-looping, an experienced engineer follows a standard debugging flow:

1. **Check the service status** — `systemctl status api-gateway.service` gives you a quick overview including the current state, recent exit codes, and the last few log lines.
2. **Read the full logs** — `journalctl -u api-gateway.service` shows the complete history of the service's attempts to start, including the exact error messages that explain why it's failing.
3. **Inspect the unit file** — `cat /etc/systemd/system/api-gateway.service` to read the actual configuration. Cross-reference every path, user, and setting against what actually exists on the system.
4. **Fix, reload, restart** — after fixing the unit file, you must run `systemctl daemon-reload` before restarting, because systemd caches unit files in memory.

## Step-by-Step Solution

### Step 1: Check the service status

```bash
systemctl status api-gateway.service
```

**What this does:** Shows the current state of the service. You'll see it's in a "failed" or "activating (auto-restart)" state, along with the exit code and recent log entries. This gives you the first clues about what's going wrong.

### Step 2: Read the detailed logs

```bash
journalctl -u api-gateway.service -n 30
```

**What this does:** Shows the last 30 log entries for this specific service. The `-u` flag filters by unit name, and `-n 30` limits to the most recent 30 lines. You'll see repeated error messages about the service failing to start. Look for messages about "No such file or directory," "user not found," or similar errors.

### Step 3: Inspect the unit file

```bash
cat /etc/systemd/system/api-gateway.service
```

**What this does:** Shows the full service configuration. Read it carefully and check:
- Does the path in `ExecStart` actually exist? (Check with `ls /opt/api-gatway.py` — notice the typo)
- Does the `WorkingDirectory` exist? (Check with `ls -d /opt/api-gateway`)
- Does the `User` exist? (Check with `id apigateway`)

### Step 4: Fix the ExecStart typo

```bash
sed -i 's|/opt/api-gatway.py|/opt/api-gateway.py|' /etc/systemd/system/api-gateway.service
```

**What this does:** Fixes the typo in the Python script path — changing `api-gatway.py` (missing "e") to `api-gateway.py` (correct spelling). We use `|` as the sed delimiter instead of `/` to avoid conflicts with the forward slashes in file paths.

### Step 5: Create the WorkingDirectory

```bash
mkdir -p /opt/api-gateway
```

**What this does:** Creates the working directory that the unit file expects. The `-p` flag means "create parent directories as needed" and "don't error if it already exists." Systemd requires the WorkingDirectory to exist before it will start the service.

### Step 6: Create the required user

```bash
useradd --system --no-create-home --shell /usr/sbin/nologin apigateway
```

**What this does:** Creates a system user called `apigateway`. The flags are best practices for service accounts:
- `--system` — creates a system user (lower UID range, no aging info)
- `--no-create-home` — don't create a home directory (services don't need one)
- `--shell /usr/sbin/nologin` — prevents anyone from logging in as this user interactively (security best practice for service accounts)

### Step 7: Reload systemd and restart the service

```bash
systemctl daemon-reload
systemctl restart api-gateway.service
```

**What this does:** `daemon-reload` tells systemd to re-read all unit files from disk — this is required whenever you change a `.service` file, because systemd caches the configuration in memory. Then `restart` stops and starts the service with the new configuration.

### Step 8: Verify the service is running

```bash
systemctl status api-gateway.service
```

**What this does:** Confirms the service is now "active (running)" instead of crash-looping. Check that it's been running for more than a few seconds — if it's still crash-looping, the uptime would reset every second.

### Step 9: Test the application

```bash
curl -s http://localhost:3000
```

**What this does:** Sends an HTTP request to the API gateway, which should respond with `{"status":"ok"}`. This confirms the application is not only running but actually serving requests correctly.

## Docker Lab vs Real Life

- **Systemd in Docker:** This lab uses a Docker container with systemd inside, which requires special configuration (running in privileged mode with `/sbin/init` as the entrypoint). In normal Docker usage, you wouldn't use systemd at all — containers typically run a single process directly.
- **Journal persistence:** In this lab, `journalctl` logs are stored in memory. On a real server, journal logs are persisted to `/var/log/journal/` and survive reboots, giving you historical data to investigate when things went wrong.
- **Service hardening:** On a production server, you'd also add security directives to the unit file like `ProtectSystem=strict`, `PrivateTmp=true`, `NoNewPrivileges=true`, etc. These restrict what the service process can do if it's compromised.
- **Crash loop detection:** Systemd has built-in rate limiting for restarts (`StartLimitIntervalSec` and `StartLimitBurst`). After too many rapid failures, it stops trying and marks the service as "failed." On a real server, your monitoring system would alert on this.

## Key Concepts Learned

- **`systemctl status` and `journalctl -u` are your primary debugging tools** for systemd services — always check these first
- **`systemctl daemon-reload` is required after editing unit files** — systemd caches configuration in memory and won't see your changes without a reload
- **Every path, user, and directory in a unit file must actually exist** — systemd validates these before starting the service, and any mismatch causes an immediate failure
- **`Restart=always` can mask problems** — the service keeps restarting so fast you might not realize it's broken unless you check the logs
- **Typos in configuration are one of the most common causes of service failures** — always verify paths by checking them against the actual filesystem

## Common Mistakes

- **Forgetting `systemctl daemon-reload`** — this is the most common systemd mistake. You edit the unit file, restart the service, and wonder why your changes didn't take effect. Systemd is still using the cached version.
- **Only fixing one issue and thinking the service should work** — like many real-world problems, there are multiple things wrong. You need to fix all of them before the service will start successfully.
- **Not checking if the User exists** — it's easy to overlook the `User=` directive in the unit file. If the user doesn't exist, the service can't start, and the error message may not be immediately obvious.
- **Removing `Restart=always` instead of fixing the root cause** — the restart directive isn't the problem; it's doing its job. The underlying issues (typo, missing directory, missing user) are what need to be fixed.
- **Not testing the application after the service starts** — just because systemd says "active (running)" doesn't mean the application is working correctly. Always test the actual functionality.
