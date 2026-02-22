# Solution Walkthrough — Port Conflict

## The Problem

The API service (`/opt/api.py`) needs to run on port 8080, but it can't start because **a stale process is already occupying that port**. The stale process is a leftover from a previous deployment or debugging session — it's responding with HTTP 503 ("Service Unavailable") and the text "Stale process," which means it's not serving any useful function.

In Linux, only one process can bind to a specific port at a time (on the same interface). When you try to start a second process on an already-occupied port, you get an "Address already in use" error (errno `EADDRINUSE`). The legitimate API service can't start until the squatter is removed.

This is an extremely common production scenario — old processes that didn't shut down cleanly, debugging servers left running, or duplicate deployments can all cause port conflicts.

## Thought Process

When a service fails to start with "Address already in use," an experienced engineer follows a straightforward process:

1. **Find what's using the port** — use `ss -tlnp | grep 8080` or `lsof -i :8080` to identify the PID and name of the process occupying the port.
2. **Determine if it's legitimate** — is this a real service that should be running, or a stale/rogue process? Check its command line with `ps -p <PID> -o cmd`.
3. **Kill the squatter** — once you've confirmed it's not a service you need, kill it with `kill <PID>`.
4. **Start the real service** — now that the port is free, start the legitimate application.
5. **Verify** — confirm the real service is running and responding correctly.

## Step-by-Step Solution

### Step 1: Try to start the API (observe the error)

```bash
python3 /opt/api.py &
```

**What this does:** Attempts to start the API service. It will fail with an "Address already in use" error because port 8080 is already taken by the stale process. This confirms the diagnosis.

### Step 2: Find what's using port 8080

```bash
ss -tlnp | grep 8080
```

**What this does:** Shows which process is listening on port 8080. The flags: `-t` for TCP, `-l` for listening sockets, `-n` for numeric ports (don't resolve names), `-p` for process information. You'll see a Python process occupying the port.

### Step 3: Identify the process

```bash
ps aux | grep "Stale process"
```

**What this does:** Searches running processes for the stale process by its identifying text. You'll see the inline Python script that's serving "Stale process" responses. Note the PID (the second column).

### Step 4: Get the exact PID

```bash
lsof -i :8080 -t
```

**What this does:** Shows only the PID(s) of processes using port 8080. The `-i :8080` flag filters by port, and `-t` outputs only the PID (terse mode), making it easy to use in scripts. This is cleaner than parsing `ss` output.

### Step 5: Kill the stale process

```bash
kill $(lsof -i :8080 -t)
```

**What this does:** Sends a SIGTERM (graceful shutdown) signal to the process occupying port 8080. The `$(...)` syntax runs the inner command first and substitutes its output (the PID) into the `kill` command. SIGTERM gives the process a chance to clean up before exiting.

### Step 6: Verify the port is now free

```bash
ss -tlnp | grep 8080
```

**What this does:** Confirms that nothing is listening on port 8080 anymore. The output should be empty, meaning the port is free for the real API service.

### Step 7: Start the legitimate API service

```bash
python3 /opt/api.py &
```

**What this does:** Starts the actual API service in the background. The `&` at the end runs it as a background process so you get your shell back. This time it will successfully bind to port 8080 because the port is no longer occupied.

### Step 8: Verify the API is running and responding correctly

```bash
curl -s http://localhost:8080
```

**What this does:** Sends an HTTP request to the API. You should see "API OK" — the legitimate response from `/opt/api.py`, not the "Stale process" response from the old squatter.

## Docker Lab vs Real Life

- **Process management:** In this lab, we start the API manually with `python3 /opt/api.py &`. In production, services would be managed by systemd, which handles starting, stopping, and restarting automatically. Systemd would also automatically restart the service if it crashes.
- **Finding port conflicts:** On a real server, `lsof -i :PORT` is the go-to command. Some minimal installations don't have `lsof` installed, in which case `ss -tlnp` is always available. On modern systems, `fuser 8080/tcp` is another option.
- **Graceful deployment:** In production, you'd use deployment tools that handle port transitions gracefully — blue/green deployments, rolling updates in Kubernetes, or systemd's socket activation. These avoid the gap between killing the old process and starting the new one.
- **SO_REUSEADDR:** Sometimes after killing a process, the port stays in a `TIME_WAIT` state for up to 60 seconds. Applications should set the `SO_REUSEADDR` socket option to allow binding to ports in this state. If you see "Address already in use" after killing a process, this might be why.

## Key Concepts Learned

- **Only one process can bind to a port at a time** — this is a fundamental TCP/IP rule. Attempting to bind a second process to the same port results in "Address already in use."
- **`ss -tlnp` and `lsof -i :PORT` find port users** — these are the two essential commands for diagnosing port conflicts
- **Always identify before killing** — make sure the process on the port is actually stale/rogue before killing it. It could be a legitimate service you'd break.
- **Kill the old process before starting the new one** — the port must be free before the new service can bind to it
- **`lsof -i :PORT -t` gives just the PID** — useful for scripting: `kill $(lsof -i :8080 -t)`

## Common Mistakes

- **Starting the new service without checking the port first** — the start will fail with "Address already in use," and the error message might not be immediately obvious, especially in application logs.
- **Using `kill -9` as a first resort** — always try `kill` (SIGTERM) first. `kill -9` (SIGKILL) doesn't let the process clean up, which can leave behind temporary files, corrupt data, or leave the port in TIME_WAIT longer.
- **Killing the wrong process** — if you `killall python3`, you might take out other legitimate Python services. Always target by specific PID.
- **Forgetting to start the real service after killing the squatter** — freeing the port is only half the job. You still need to start the actual application.
- **Not investigating why the stale process was there** — in production, you'd want to understand how this happened. Was it a failed deployment? A debugging session someone forgot to clean up? A duplicate service definition? Fixing the symptom without understanding the cause means it'll happen again.
