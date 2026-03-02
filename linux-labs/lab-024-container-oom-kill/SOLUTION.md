# Solution Walkthrough — Container OOM Kill

## TLDR

A container has been set up with only 32MB of memory, but the workload inside it needs about 128MB. Think of it like trying to run a dishwasher on a trickle of water — it just can't do the job. When a container tries to use more memory than Docker allows, the Linux kernel steps in and kills the process outright. No warning, no graceful shutdown — just dead. This is called an OOM (Out of Memory) kill.

The fix: remove the broken container and recreate it with a sensible memory limit (256MB). You don't remove the limit entirely — that would leave the host unprotected — you just give the container enough room to do its job.

---

## Environment Limitation — Read This First

**If you're running Docker-in-Docker** (e.g. on a Raspberry Pi running Docker inside a container), your kernel may not support cgroup memory limits. You'll see a warning like:

```
WARNING: Your kernel does not support memory limit capabilities or the cgroup is not mounted. Limitation discarded.
```

This means Docker **cannot enforce memory limits** in your environment. The container won't actually get OOM killed, and `docker inspect` will show `"Memory": 0` regardless of what you pass with `--memory`. The validation checks for memory limits will fail — not because you did anything wrong, but because the environment can't support this feature.

The commands and concepts are still correct. If you have access to a cloud VM or a bare-metal Docker install, revisit this lab there to see the real OOM kill behaviour.

---

## The Problem

A data processing container keeps crashing. Docker restarts it, and it crashes again — stuck in a loop. Your job is to figure out why and fix it.

## Thought Process

When a container keeps dying unexpectedly, an experienced engineer checks for OOM kills:

1. **Check what's running** — `docker ps -a` to see the container's state (is it running, exited, restarting?)
2. **Check for OOM kills** — inspect the container to see if the kernel killed it for using too much memory
3. **Check the memory limit** — see what limit Docker applied and whether it's realistic for the workload
4. **Fix the limit** — remove the broken container and recreate it with a sensible memory limit

---

## Step-by-Step Solution

### Step 1: Look around the environment

Before doing anything, check what's already running and what tools are available.

```bash
docker ps -a
```

**Command breakdown:**
- `docker ps` — lists running containers
- `-a` — includes stopped/crashed containers too, not just running ones

You'll see nothing relevant yet — no data processor container exists.

Now look for setup scripts:

```bash
ls /opt/
```

You'll spot `run-processor.sh`. Read it before running it:

```bash
cat /opt/run-processor.sh
```

This shows you the script will create a container called `data-processor` with `--memory=32m` running a Python workload.

### Step 2: Run the processor setup script

```bash
/opt/run-processor.sh
```

This starts the data processor container. In an environment with cgroup support, the container will start allocating memory and quickly get OOM killed. In Docker-in-Docker setups, the memory limit won't be enforced and the container will run fine (see environment limitation above).

### Step 3: Check the container state

```bash
docker ps -a
```

In a working environment, you'd see the container in an `Exited` or `Restarting` state. In Docker-in-Docker, it'll show as `Up`.

### Step 4: Check for OOM kill and memory limit

The quickest way to investigate is to dump the full inspection and search through it:

```bash
docker inspect data-processor | grep -i oom
docker inspect data-processor | grep -i memory
```

**Command breakdown:**
- `docker inspect data-processor` — dumps all configuration and state info for the container as JSON
- `| grep -i oom` — pipes that output to grep, searching for "oom" (case-insensitive thanks to `-i`)
- `| grep -i memory` — same idea, searching for "memory"

**What you're looking for:**
- `"OOMKilled": true` — confirms the container was killed for exceeding its memory limit
- `"Memory": 33554432` — that's 32MB in bytes (32 × 1024 × 1024), which is the limit that's too low

**In Docker-in-Docker you'll see:**
- `"OOMKilled": false` — because the limit wasn't enforced
- `"Memory": 0` — Docker couldn't apply the limit so it shows zero (unlimited)

If you want to query specific fields directly (useful in scripts), the Go template syntax works too:

```bash
docker inspect data-processor --format '{{.State.OOMKilled}}'
docker inspect data-processor --format '{{.HostConfig.Memory}}'
```

**Command breakdown:**
- `--format '{{.State.OOMKilled}}'` — uses Go template syntax to pull out just one field from the JSON
- `.State.OOMKilled` — navigates the JSON structure: State object → OOMKilled field
- `.HostConfig.Memory` — navigates to: HostConfig object → Memory field (value in bytes)

The grep method is easier to remember for interactive troubleshooting. The `--format` method is better when scripting or when you know exactly which field you need.

### Step 5: Check container logs

```bash
docker logs data-processor
```

**Command breakdown:**
- `docker logs` — shows whatever the container printed to stdout/stderr
- `data-processor` — the container name

You might see partial output or nothing useful. OOM kills are abrupt — the kernel kills the process immediately with no chance to log a clean error message. This is why checking `OOMKilled` via inspect is more reliable than reading logs.

### Step 6: Remove the broken container

```bash
docker rm -f data-processor
```

**Command breakdown:**
- `docker rm` — removes a container
- `-f` — force removal, works even if the container is still running
- `data-processor` — the container name

### Step 7: Recreate with an appropriate memory limit

```bash
docker run -d --name data-processor \
    --memory=256m \
    python:3.11-slim python3 -c "
import time
data = []
for i in range(100):
    data.append('X' * 1024 * 1024)
    time.sleep(0.1)
print('Processing complete')
time.sleep(3600)
"
```

**Command breakdown:**
- `docker run` — creates and starts a new container
- `-d` — detached mode (runs in the background)
- `--name data-processor` — gives the container a name so we can refer to it later
- `--memory=256m` — sets the memory limit to 256 megabytes (was 32m before)
- `python:3.11-slim` — the container image to use
- `python3 -c "..."` — the command to run inside the container (a Python script that allocates ~128MB)
- `\` — line continuation, just lets you split a long command across multiple lines for readability

**Why 256MB and not 128MB?** The workload allocates about 128MB of data, but the Python runtime itself needs memory too (interpreter, garbage collector, etc.). Setting the limit at exactly what the workload uses leaves no headroom. A good rule of thumb is 2x typical usage as a starting point.

**Why not remove the limit entirely?** A container without a memory limit could consume all available RAM on the host if something goes wrong (like a memory leak). The limit protects everything else running on that machine.

### Step 8: Monitor memory usage

```bash
docker stats data-processor --no-stream
```

**Command breakdown:**
- `docker stats` — shows live resource usage (CPU, memory, network, disk) for containers
- `data-processor` — the container to monitor
- `--no-stream` — shows a single snapshot and exits (without this flag, it continuously updates like `top`)

You should see memory usage growing as the workload processes data, but staying well under the 256MB limit.

### Step 9: Verify the fix

```bash
docker inspect data-processor | grep -i oom
docker inspect data-processor | grep -i memory
```

Confirm:
- `"OOMKilled": false` — the container has not been OOM killed
- `"Memory": 268435456` — that's 256MB in bytes (256 × 1024 × 1024)

Also check the container is still running:

```bash
docker ps -a
```

The container should show status `Up` rather than `Exited`.

---

## Key Concepts

- **Docker memory limits protect the host** — without limits, a single container can consume all available RAM and crash everything on the host machine
- **OOM kills are silent and abrupt** — the kernel kills the process immediately with no chance for graceful shutdown or error logging, which makes them hard to diagnose if you don't know to check `OOMKilled`
- **Exit code 137 often means OOM** — 137 = 128 + 9, meaning the process was killed by SIGKILL. But other things can cause SIGKILL too, so checking the `OOMKilled` field directly is more reliable
- **Memory limits must match workload needs** — set limits large enough for the workload plus headroom, but not so large they defeat the purpose of limiting. A good starting point is 2x typical usage
- **`docker inspect` is your diagnostic Swiss army knife** — pipe it to `grep` for quick interactive searches, or use `--format` with Go templates for scripting

## Common Mistakes

- **Removing the memory limit entirely** — "fixes" the OOM kill but leaves the host unprotected. Always set a reasonable limit.
- **Setting the limit too close to actual usage** — if the workload uses 128MB and you set 128MB, there's no room for the runtime, garbage collection, or temporary spikes. Always add headroom.
- **Only checking logs** — OOM kills often produce no log output because the process is killed instantly. Always check `docker inspect` for the `OOMKilled` field.
- **Confusing Docker and Kubernetes units** — Docker uses `m` for megabytes and `g` for gigabytes (`--memory=256m`). Kubernetes uses `Mi` (mebibytes) and `Gi` (gibibytes). They're slightly different values.

---

## Docker Lab vs Real Life

- **Finding memory needs:** In this lab we can read the code. In production, you'd use `docker stats`, Prometheus metrics, or load testing to understand actual usage under realistic workloads.
- **OOM kill monitoring:** In production, you'd set up alerts for OOM kills using `docker events --filter event=oom` or Kubernetes events. OOM kills should always trigger alerts.
- **Memory leaks:** If OOM kills keep happening even with large limits, the application probably has a memory leak. Use profiling tools (Python's `tracemalloc`, Java's heap dumps, Go's `pprof`) to find and fix the root cause.
- **Kubernetes distinction:** Kubernetes separates "requests" (guaranteed allocation) from "limits" (maximum allowed). You'd typically set requests to typical usage and limits higher with headroom. Docker only has limits.
