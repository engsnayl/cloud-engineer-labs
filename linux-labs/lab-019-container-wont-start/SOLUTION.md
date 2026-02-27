# Solution Walkthrough — Lab 019: Container Won't Start

## The Problem

A developer has built a Docker image for a payment service, but it won't work. The Dockerfile has bugs that prevent the image from building correctly, and even if you got past the build, the entrypoint references the wrong file so the container would crash immediately.

This lab is about reading Docker build errors, understanding how Dockerfiles work, and fixing common mistakes.

TLDR
The Dockerfile has two wrong filenames. The COPY line references application.py but the file is called app.py. The ENTRYPOINT references server.py but again it's app.py. Fix both, rebuild the image, run the container.

## Important: How This Lab Works

This is a **Docker lab**, which works differently from the Linux troubleshooting labs. There are two levels:

- **Your Pi's shell** (`engsnayl@pi:~$`) — where you run `lab start`, `lab validate`, `lab stop`
- **The lab container** (`root@<container-id>:/#`) — where you do the actual troubleshooting

The lab container has Docker installed inside it (via a mounted Docker socket). You'll run `docker build`, `docker run`, and other Docker commands **from inside the lab container**. Think of it as your workstation that happens to be inside a container.

> **How to tell where you are:** Look at your prompt. If it says `engsnayl@pi`, you're on the Pi. If it says `root@` followed by a hex string, you're inside the lab container.

## Thought Process

When someone says "my container won't start", the debugging order is:

1. **Look at the source files** — What's the app? What's the Dockerfile trying to do?
2. **Try to build it** — Does it even build? Read the error messages.
3. **Fix build errors** — Usually filename mismatches, missing files, or bad base images.
4. **Run it** — Does the container start and stay running?
5. **Check logs** — If it crashes, `docker logs` tells you why.
6. **Verify** — Can you reach the service?

## Step-by-Step Solution

### Step 1: Get into the lab container

```
📍 Run this on your Pi
```

```bash
docker exec -it lab019-container-wont-start bash
```

**What this does:** Opens an interactive bash shell inside the lab container. The `-it` flags mean **i**nteractive and **t**erminal — without them you'd just get a blank screen.

From this point forward, all commands are run inside the lab container unless stated otherwise.

---

### Step 2: Explore the project files

```
📍 Run this inside the lab container
```

```bash
ls /opt/payment-service/
```

**What you'll see:**
```
Dockerfile  app.py
```

The application code (`app.py`) and the Dockerfile that's supposed to build it. Let's understand what the app does first:

```bash
cat /opt/payment-service/app.py
```

**What you'll see:** A simple Python HTTP server that listens on port 5000 and responds with "Payment Service OK". Note the filename: it's called **`app.py`**. Keep that in mind.

---

### Step 3: Read the Dockerfile

```bash
cat /opt/payment-service/Dockerfile
```

**What you'll see:**
```dockerfile
FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fault 1: Copy wrong filename
COPY application.py .

# Fault 2: Wrong entrypoint
ENTRYPOINT ["python3", "server.py"]
```

Even before trying to build, you can spot potential issues by comparing the Dockerfile to the actual files. The COPY references `application.py`, but the file is called `app.py`. The ENTRYPOINT references `server.py`, but again the file is `app.py`.

But let's not just guess — let's **build it and let Docker tell us what's wrong**.

---

### Step 4: Try to build the image

```bash
docker build -t payment-service /opt/payment-service/
```

**What this does:**
- `docker build` tells Docker to build an image from a Dockerfile
- `-t payment-service` tags (names) the resulting image as "payment-service"
- `/opt/payment-service/` is the **build context** — the directory Docker will use to find files referenced in COPY/ADD instructions

**What you'll see:**
```
=> ERROR [3/3] COPY application.py .
------
 > [3/3] COPY application.py .:
------
failed to solve: failed to compute cache key: failed to calculate checksum of ref: "/application.py": not found
```

**What this means:** Docker tried to copy `application.py` from the build context (the `/opt/payment-service/` directory) into the image, but that file doesn't exist. The actual file is called `app.py`.

---

### Step 5: Fix the Dockerfile — COPY line

Open the Dockerfile in an editor:

```bash
vim /opt/payment-service/Dockerfile
```

**If you're not comfortable with vim**, here's a quick survival guide:
- Press `i` to enter insert mode (you can now type and edit)
- Make your changes
- Press `Esc` to exit insert mode
- Type `:wq` and press Enter to save and quit

**Or use sed** to do it in one command:

```bash
sed -i 's/COPY application.py/COPY app.py/' /opt/payment-service/Dockerfile
```

**What `sed -i 's/old/new/'` does:** Finds `old` text and replaces it with `new` text, editing the file in place (`-i`).

---

### Step 6: Build again

```bash
docker build -t payment-service /opt/payment-service/
```

**What you'll see:** This time the build succeeds! Docker pulls the `python:3.11-slim` base image (this might take a minute on the Pi), installs curl, copies `app.py` into the image, and finishes.

You might think you're done — but there's still the entrypoint issue. The build succeeded because COPY only checks that the source file exists in the build context. The ENTRYPOINT just records what command to run later; Docker doesn't check whether that file actually exists inside the image until you try to **run** it.

---

### Step 7: Try to run the container

```bash
docker run -d --name payment-service payment-service
```

**What this does:**
- `docker run` creates and starts a container from an image
- `-d` runs it in **d**etached mode (in the background)
- `--name payment-service` gives the container a human-readable name
- The last `payment-service` is the image name we built in the previous step

**What happens:** The command returns a container ID, which looks like success. But let's check:

```bash
docker ps -a --filter "name=payment-service"
```

**What you'll see:**
```
CONTAINER ID   IMAGE             COMMAND              CREATED          STATUS                     PORTS   NAMES
abc123def456   payment-service   "python3 server.py"  5 seconds ago    Exited (2) 3 seconds ago           payment-service
```

**Key detail:** The STATUS column says "Exited (2)" — the container started and immediately crashed. Exit code 2 from Python means the file wasn't found. And look at the COMMAND column: it says `python3 server.py`. But our file is called `app.py`, not `server.py`.

---

### Step 8: Check the logs to confirm

```bash
docker logs payment-service
```

**What this does:** `docker logs` shows everything the container printed to stdout/stderr before it exited. This is the single most useful command for debugging crashed containers.

**What you'll see:**
```
python3: can't open file '/app/server.py': [Errno 2] No such file or directory
```

This confirms it: the ENTRYPOINT is telling Python to run `server.py`, but the file inside the container is `app.py` (because that's what we COPY'd in).

---

### Step 9: Fix the Dockerfile — ENTRYPOINT line

First, remove the crashed container (you can't reuse the name while it exists):

```bash
docker rm payment-service
```

**What this does:** Removes the stopped container. You can't have two containers with the same name, so you need to remove the old one before creating a new one.

Now fix the entrypoint:

```bash
sed -i 's/server.py/app.py/' /opt/payment-service/Dockerfile
```

Let's verify the Dockerfile looks right now:

```bash
cat /opt/payment-service/Dockerfile
```

**What you should see:**
```dockerfile
FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY app.py .

ENTRYPOINT ["python3", "app.py"]
```

That looks correct — it copies `app.py` and runs `app.py`.

---

### Step 10: Rebuild and run

```bash
docker build -t payment-service /opt/payment-service/
docker run -d --name payment-service payment-service
```

**What you'll see:** The build completes quickly this time (Docker caches layers it's already built). The run command returns a container ID.

---

### Step 11: Verify the container is running

```bash
docker ps --filter "name=payment-service"
```

**What you'll see:**
```
CONTAINER ID   IMAGE             COMMAND             CREATED          STATUS         PORTS   NAMES
abc123def456   payment-service   "python3 app.py"    5 seconds ago    Up 4 seconds           payment-service
```

**Key details:** STATUS says "Up" (not "Exited"), and COMMAND says `python3 app.py`. The container is running.

---

### Step 12: Verify the service responds

First, check the logs:

```bash
docker logs payment-service
```

**What you'll see:** Possibly nothing, or `Payment service starting on port 5000...`. If the output is blank, that's because Python buffers stdout inside containers by default — the print statement ran but the output is stuck in a buffer. This is a common Docker gotcha. In production you'd fix it by adding `ENV PYTHONUNBUFFERED=1` to the Dockerfile, but it doesn't affect the service itself.

Now test the HTTP endpoint. There's an important networking detail here: the payment-service container has its **own network namespace**. You can't reach it with `curl http://localhost:5000` from the lab container because `localhost` refers to *this* container, not the payment-service container. They're separate containers on separate networks.

The simplest way to test is to run curl **from inside the payment-service container**:

```bash
docker exec payment-service curl -s http://localhost:5000
```

**What this does:** `docker exec` runs a command inside the payment-service container. Inside that container, `localhost` correctly refers to itself — which is where the server is listening on port 5000. We included curl in the Dockerfile for exactly this purpose.

**What you'll see:**
```
Payment Service OK
```

The service is running and responding. You're done!

---

### Step 13: Validate

```
📍 Run this on your Pi (open a new terminal or exit the lab container first)
```

```bash
lab validate 019
```

All checks should pass.

## Summary of What Was Broken

| Fault | File | What was wrong | How you found it |
|-------|------|---------------|-----------------|
| Wrong COPY filename | Dockerfile | `COPY application.py .` but the file is `app.py` | `docker build` failed with "not found" error |
| Wrong ENTRYPOINT filename | Dockerfile | `ENTRYPOINT ["python3", "server.py"]` but the file is `app.py` | Container exited immediately; `docker logs` showed "can't open file" |

## Docker Lab vs Real Life

**docker build:** Identical in production. You'd typically run this in a CI/CD pipeline (GitHub Actions, Jenkins, etc.) rather than manually, but the command and Dockerfile syntax are exactly the same.

**docker logs:** This is your first port of call for any crashed container, both locally and in production. In Kubernetes, the equivalent is `kubectl logs <pod-name>`.

**docker ps -a:** The `-a` flag is crucial. Without it, you only see running containers. Crashed containers are invisible without `-a`. This catches people out constantly.

**Build context:** In this lab, the build context is a local directory. In CI/CD, it's usually the repo root. Either way, Docker can only COPY files that are inside the build context.

**Port publishing:** In this lab we tested the service from inside its own container using `docker exec`. In production, you'd run `docker run -d -p 5000:5000 --name payment-service payment-service` to publish port 5000 to the host, making it accessible from outside. The `-p hostPort:containerPort` flag maps a port on the host to a port inside the container.

**Docker socket vs Docker network:** Mounting the Docker socket (`/var/run/docker.sock`) lets a container *manage* other containers (build, run, inspect, logs). But it does **not** share their network. Each container gets its own network namespace. This distinction matters — being able to `docker exec` into a container doesn't mean you can `curl` its ports from yours.

## Key Concepts Learned

- **`docker build -t <n> <path>`** builds an image from a Dockerfile in the given directory
- **`docker run -d --name <n> <image>`** starts a container in the background
- **`docker ps -a`** shows ALL containers including crashed ones — without `-a` you only see running containers
- **`docker logs <container>`** shows stdout/stderr output — your first debugging tool for crashed containers
- **`docker rm <container>`** removes a stopped container (required before reusing the name)
- **`docker exec <container> <command>`** runs a command inside a running container
- **COPY** in a Dockerfile references files in the build context — the filename must match exactly
- **ENTRYPOINT** defines what runs when the container starts — if it references a file that doesn't exist in the image, the container crashes
- Build errors and runtime errors are different: a Dockerfile can build successfully but still produce a container that crashes
- **Docker socket ≠ Docker network:** mounting the socket lets you manage containers, but each container still has its own isolated network
- **Python stdout buffering:** Python buffers print output in containers by default — add `ENV PYTHONUNBUFFERED=1` to Dockerfiles to fix this

## Common Mistakes

- **Running `docker ps` without `-a`:** If you're looking for a crashed container and forget `-a`, you'll see nothing and think the container was never created. Always use `docker ps -a` when debugging.
- **Forgetting to `docker rm` before re-running:** Docker won't let you create two containers with the same name. You'll get "name already in use". Remove the old one first with `docker rm`.
- **Not reading `docker logs`:** Many people skip straight to inspecting the Dockerfile instead of just asking Docker what went wrong. `docker logs` usually tells you exactly what happened.
- **Confusing build context with the container filesystem:** `COPY app.py .` copies from the build directory on your machine into the image. The `.` destination refers to WORKDIR inside the image, not your current directory.
- **Running Docker commands on the Pi instead of inside the lab container:** In these Docker labs, the troubleshooting happens inside the lab container (which has Docker access via the mounted socket). The Pi shell is just for `lab start`, `lab validate`, and `lab stop`.
- **Assuming localhost works across containers:** Each container has its own network. `curl http://localhost:5000` from one container won't reach a server in a different container. Use `docker exec` to run commands inside the target container, or put containers on the same Docker network.
