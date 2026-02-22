# Solution Walkthrough — Container Won't Start

## The Problem

A Docker container for the "payment-service" is built from a Dockerfile, but the container immediately exits after starting because the Dockerfile has **two filename mistakes**:

1. **COPY references the wrong filename** — the Dockerfile says `COPY application.py .` but the actual file is called `app.py`. The Docker build fails (or succeeds with a missing file) because it can't find `application.py`.
2. **ENTRYPOINT references the wrong filename** — even if the COPY worked, the ENTRYPOINT says `python3 server.py`, but the file is called `app.py`. Python would exit with a "file not found" error, causing the container to crash immediately.

These are simple typos, but they represent one of the most common reasons containers fail to start. When the container exits immediately after starting, Docker reports it as "Exited" instead of "Up."

## Thought Process

When a container exits immediately after starting, an experienced engineer follows this debugging path:

1. **Check container status** — `docker ps -a` shows all containers including stopped ones. If the status shows "Exited (1)" or "Exited (2)" instead of "Up," the container crashed.
2. **Read the logs** — `docker logs <container>` shows the container's stdout/stderr output, which usually contains the error message explaining why it crashed. Look for Python tracebacks, "file not found" errors, or permission denied messages.
3. **Inspect the Dockerfile** — look at `COPY`, `ENTRYPOINT`, and `CMD` directives. Cross-reference every filename with what actually exists in the build context directory.
4. **Fix, rebuild, rerun** — after fixing the Dockerfile, you must rebuild the image and create a new container.

## Step-by-Step Solution

### Step 1: Check the container status

```bash
docker ps -a --filter "name=payment-service"
```

**What this does:** Lists all containers (including stopped ones) filtered by name. The `-a` flag is crucial — without it, `docker ps` only shows running containers, so a crashed container would be invisible. You'll see the payment-service container with status "Exited."

### Step 2: Check the container logs

```bash
docker logs payment-service
```

**What this does:** Shows the output that the container produced before it exited. You'll see an error like `python3: can't open file 'server.py': No such file or directory`. This tells you the ENTRYPOINT is referencing a file that doesn't exist inside the container.

### Step 3: Look at the application files

```bash
ls -la /opt/payment-service/
```

**What this does:** Lists the actual files in the build context directory. You'll see `app.py` and `Dockerfile`. Note the filename carefully — it's `app.py`, not `application.py` or `server.py`.

### Step 4: Look at the current Dockerfile

```bash
cat /opt/payment-service/Dockerfile
```

**What this does:** Shows the Dockerfile with its two bugs:
- `COPY application.py .` — should be `COPY app.py .`
- `ENTRYPOINT ["python3", "server.py"]` — should be `ENTRYPOINT ["python3", "app.py"]`

### Step 5: Fix the Dockerfile

```bash
cat > /opt/payment-service/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY app.py .

ENTRYPOINT ["python3", "app.py"]
EOF
```

**What this does:** Rewrites the Dockerfile with the correct filenames:
- `COPY app.py .` — copies the actual application file into the container's `/app` directory
- `ENTRYPOINT ["python3", "app.py"]` — tells Docker to run `python3 app.py` when the container starts

The rest of the Dockerfile stays the same: `FROM python:3.11-slim` uses a lightweight Python image, and `WORKDIR /app` sets the working directory.

### Step 6: Remove the broken container

```bash
docker rm -f payment-service
```

**What this does:** Removes the existing (crashed) container. The `-f` flag forces removal even if the container is somehow still running. You can't create a new container with the same name until the old one is removed.

### Step 7: Rebuild the image

```bash
docker build -t payment-service /opt/payment-service/
```

**What this does:** Builds a new Docker image from the fixed Dockerfile. Docker reads the Dockerfile, executes each instruction (pull base image, copy files, set entrypoint), and produces a new image tagged `payment-service`.

### Step 8: Run the new container

```bash
docker run -d --name payment-service payment-service
```

**What this does:** Creates and starts a new container from the fixed image. The `-d` flag runs it in detached mode (background). The `--name payment-service` gives it the name the validation script expects.

### Step 9: Verify it's running

```bash
docker ps --filter "name=payment-service"
```

**What this does:** Shows the container's status. This time you should see "Up" in the status column instead of "Exited." The container is running successfully.

### Step 10: Verify the service is working

```bash
docker exec payment-service curl -s http://localhost:5000
```

**What this does:** Runs `curl` inside the container to test the payment service. You should see "Payment Service OK" — confirming the application is running and serving requests correctly.

## Docker Lab vs Real Life

- **Image building in CI/CD:** In production, Docker images are built in CI/CD pipelines (GitHub Actions, GitLab CI, Jenkins), not manually on servers. Build failures (like wrong filenames) would be caught before the image ever reaches production.
- **Docker Compose:** In production, you'd typically use Docker Compose or Kubernetes manifests to define and run containers, rather than individual `docker run` commands. These files are version-controlled and reviewed, reducing the chance of errors.
- **Health checks:** Production Dockerfiles include a `HEALTHCHECK` instruction that tells Docker how to verify the application is working. If the health check fails, Docker can automatically restart the container.
- **Container restart policies:** In production, you'd add `--restart=unless-stopped` or `--restart=on-failure:3` so Docker automatically restarts crashed containers without manual intervention.
- **Error monitoring:** In production, container crashes would trigger alerts through monitoring systems (Datadog, PagerDuty, CloudWatch). The container logs would be shipped to a centralized logging system for investigation.

## Key Concepts Learned

- **`docker ps -a` shows stopped containers** — without the `-a` flag, crashed containers are invisible. This is the first command to run when a container seems to have disappeared.
- **`docker logs` shows why a container crashed** — the error messages in the logs almost always explain the problem. Always check logs before anything else.
- **Every filename in a Dockerfile must match reality** — `COPY`, `ENTRYPOINT`, and `CMD` all reference files that must actually exist. Typos cause immediate crashes.
- **The fix cycle is: edit Dockerfile → remove old container → rebuild image → run new container** — you can't "fix" a running container's Dockerfile. You must rebuild from scratch.
- **`ENTRYPOINT` vs `CMD`** — `ENTRYPOINT` defines the command that always runs. `CMD` provides default arguments that can be overridden. For application containers, `ENTRYPOINT` is the right choice.

## Common Mistakes

- **Trying to fix the file inside the running container** — while you could `docker exec` into the container and fix things, this doesn't fix the Dockerfile. The next time you create a container from the image, it would be broken again. Always fix the Dockerfile.
- **Rebuilding the image without removing the old container** — `docker run --name payment-service` will fail if a container with that name already exists (even if it's stopped). Remove it first with `docker rm`.
- **Not checking `docker logs`** — many people jump straight to inspecting the Dockerfile without reading the error message. The logs tell you exactly what's wrong.
- **Forgetting to rebuild after fixing the Dockerfile** — editing the Dockerfile doesn't change the existing image. You must run `docker build` again to create a new image with your fixes.
- **Case sensitivity** — Docker, Python, and Linux are all case-sensitive. `App.py`, `app.py`, and `APP.py` are three different files. Always match case exactly.
