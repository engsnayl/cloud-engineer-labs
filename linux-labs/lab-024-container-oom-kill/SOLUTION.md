# Solution Walkthrough — Container OOM Kill

## The Problem

A data processing container is being OOM (Out of Memory) killed by Docker because its **memory limit is set too low**. The container has a 32MB memory limit (`--memory=32m`), but the workload needs approximately 128MB of memory to complete its processing. When the process inside the container tries to allocate more memory than the limit allows, the Linux kernel's OOM killer terminates it.

The container doesn't just crash once — Docker may automatically restart it (depending on the restart policy), and it will keep getting OOM killed in a cycle because the memory limit is still too low.

The fix isn't to remove the memory limit entirely — **you should still have a limit**, but it needs to be large enough for the workload to complete successfully. The validation requires a limit of at least 256MB.

## Thought Process

When a container keeps dying unexpectedly, an experienced engineer checks for OOM kills:

1. **Check the container state** — `docker inspect <container> --format '{{.State.OOMKilled}}'` tells you directly if the last exit was caused by an OOM kill.
2. **Check the current memory limit** — `docker inspect <container> --format '{{.HostConfig.Memory}}'` shows the limit in bytes.
3. **Understand the workload's memory needs** — look at the application code or use `docker stats` to monitor real-time memory usage.
4. **Set an appropriate limit** — large enough for the workload to complete, with some headroom, but not so large that a memory leak could consume all host memory.

The key principle: memory limits protect the host from runaway containers. A container without a memory limit could consume all available RAM and crash other containers or the host itself. But the limit must be realistic for the workload.

## Step-by-Step Solution

### Step 1: Run the processor setup script

```bash
/opt/run-processor.sh
```

**What this does:** Starts the data processor container with a 32MB memory limit. The container will start, begin allocating memory, and quickly get OOM killed.

### Step 2: Check if the container was OOM killed

```bash
docker inspect data-processor --format '{{.State.OOMKilled}}'
```

**What this does:** Queries the container's state to check if it was killed by the OOM killer. You'll see `true`, confirming this is an out-of-memory situation.

### Step 3: Check the current memory limit

```bash
docker inspect data-processor --format '{{.HostConfig.Memory}}'
```

**What this does:** Shows the container's memory limit in bytes. You'll see `33554432` — which is 32MB (32 × 1024 × 1024). This is far too low for a workload that allocates ~128MB.

### Step 4: Check container logs for the error

```bash
docker logs data-processor
```

**What this does:** Shows any output the container produced before it was killed. You might see partial output or nothing at all — OOM kills are abrupt, and the process doesn't get a chance to log a clean error message.

### Step 5: Remove the OOM-killed container

```bash
docker rm -f data-processor
```

**What this does:** Removes the dead container so we can create a new one with a higher memory limit. The `-f` flag forces removal.

### Step 6: Recreate with an appropriate memory limit

```bash
docker run -d --name data-processor \
    --memory=256m \
    python:3.11-slim python3 -c "
import time
# Simulate a data processing workload that needs ~128MB
data = []
for i in range(100):
    data.append('X' * 1024 * 1024)  # 1MB chunks
    time.sleep(0.1)
print('Processing complete')
time.sleep(3600)
"
```

**What this does:** Starts the same data processing workload, but with `--memory=256m` (256MB) instead of 32MB. This gives the workload plenty of room for its ~128MB allocation plus Python runtime overhead. The 256MB limit still protects the host from runaway memory consumption.

### Step 7: Monitor memory usage in real time

```bash
docker stats data-processor --no-stream
```

**What this does:** Shows a snapshot of the container's resource usage including memory. The `--no-stream` flag gives a single snapshot instead of continuously updating. You should see memory usage growing as the workload processes data, but staying well under the 256MB limit.

### Step 8: Verify the container is still running (not OOM killed)

```bash
docker inspect data-processor --format 'Running: {{.State.Running}} | OOMKilled: {{.State.OOMKilled}}'
```

**What this does:** Confirms two things: the container is still running (`true`) and has not been OOM killed (`false`). Both conditions must be met for success.

### Step 9: Verify the memory limit is set correctly

```bash
docker inspect data-processor --format '{{.HostConfig.Memory}}'
```

**What this does:** Confirms the memory limit is 268435456 bytes (256MB). The validation requires a limit of at least 256MB — you shouldn't remove the limit entirely, just set it to an appropriate value.

## Docker Lab vs Real Life

- **Determining memory needs:** In this lab, we can read the code to see it needs ~128MB. In production, you'd use `docker stats`, Prometheus metrics, or load testing to determine a container's actual memory usage under realistic workloads. Add 50-100% headroom above typical usage.
- **Memory limit vs request:** In Kubernetes, there's a distinction between "requests" (guaranteed allocation) and "limits" (maximum allowed). Docker only has limits. In Kubernetes, you'd set `resources.requests.memory: 128Mi` and `resources.limits.memory: 256Mi`.
- **OOM kill monitoring:** In production, you'd monitor for OOM kills using Docker events (`docker events --filter event=oom`), or through Kubernetes events and alerts. OOM kills should trigger alerts because they indicate either insufficient limits or a memory leak.
- **Swap:** Docker containers can also use swap if configured with `--memory-swap`. By default, a container with `--memory=256m` can also use 256MB of swap (512MB total). You can disable swap for a container with `--memory-swap=256m` (setting it equal to memory).
- **Memory leak detection:** In production, if OOM kills keep happening even with large limits, the application probably has a memory leak. Use profiling tools (Python's `tracemalloc`, Java's heap dumps, Go's `pprof`) to find and fix the leak.

## Key Concepts Learned

- **Docker memory limits protect the host** — without limits, a single container can consume all available RAM and crash everything on the host
- **`docker inspect` reveals OOM kills** — the `State.OOMKilled` field tells you directly if the container was killed by the OOM killer
- **Memory limits must match workload needs** — set limits large enough for the workload to complete, with headroom, but not so large that they defeat the purpose of limiting
- **OOM kills are abrupt** — the kernel kills the process immediately with no opportunity for graceful shutdown or error logging. This is why they're hard to diagnose without checking `OOMKilled`.
- **`docker stats` monitors live resource usage** — use it to understand a container's actual memory consumption before setting limits

## Common Mistakes

- **Removing the memory limit entirely** — while this "fixes" the OOM kill, it's a bad practice. Without limits, a memory leak or unexpected workload spike can take down the entire host. Always set a reasonable limit.
- **Setting the limit too close to actual usage** — if the workload uses 128MB and you set the limit to 128MB, there's no headroom for the Python runtime, garbage collection spikes, or temporary allocations. Always add headroom (2x typical usage is a good starting point).
- **Not checking `OOMKilled`** — many people see a crashed container and look at logs, but OOM kills often produce no log output. Checking `docker inspect` for `OOMKilled: true` is the definitive diagnostic.
- **Confusing container exit codes** — an OOM-killed container typically exits with code 137 (128 + 9, meaning killed by SIGKILL). But other causes can also produce exit code 137, so checking the `OOMKilled` field directly is more reliable.
- **Setting limits in the wrong units** — Docker accepts `m` for megabytes, `g` for gigabytes. `--memory=256m` is 256 megabytes. Don't confuse with Kubernetes, which uses `Mi` (mebibytes) and `Gi` (gibibytes).
