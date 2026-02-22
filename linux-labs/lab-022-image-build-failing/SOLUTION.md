# Solution Walkthrough — Image Build Failing

## The Problem

A Node.js application has a Dockerfile that fails to build because of **four issues**:

1. **Non-existent base image tag** — the Dockerfile uses `FROM node:23-alpine`, but Node.js version 23 doesn't exist on Docker Hub. Docker can't pull the base image, so the build fails immediately.
2. **`RUN npm install` before copying package.json** — the Dockerfile runs `npm install` before any `COPY` instruction, so there's no `package.json` in the container. npm doesn't know what to install and either errors out or does nothing.
3. **Missing COPY instructions** — the lines that copy `package.json` and `app.js` into the container are commented out. Without these files, there's nothing to install or run.
4. **Suboptimal CMD syntax** — `CMD npm start` uses the "shell form" which runs the command through `/bin/sh -c`. While this works, the "exec form" `CMD ["npm", "start"]` is preferred because it runs npm directly as PID 1, making signal handling work correctly.

## Thought Process

When `docker build` fails, an experienced engineer reads the error output carefully:

1. **First error wins** — Docker builds execute instructions top-to-bottom. Fix the first error, rebuild, and see if the next instruction works. Don't try to fix everything at once without understanding what each error means.
2. **Check the base image** — does the tag actually exist on Docker Hub? You can verify at `hub.docker.com` or by trying `docker pull node:23-alpine`.
3. **Think about instruction order** — Docker layers are sequential. You can't use a file before it's been COPY'd into the image. The typical pattern is: COPY dependency files → install dependencies → COPY application code.
4. **Optimal layer caching** — copy `package.json` first and run `npm install`, then copy the rest of the source. This way, the `npm install` layer is cached and only re-runs when dependencies change, not when application code changes.

## Step-by-Step Solution

### Step 1: Try building to see the errors

```bash
docker build -t webapp:fixed /opt/webapp/
```

**What this does:** Attempts to build the Docker image. It will fail on the very first instruction because `node:23-alpine` doesn't exist. Reading the error message tells you exactly what's wrong.

### Step 2: Look at the current Dockerfile

```bash
cat /opt/webapp/Dockerfile
```

**What this does:** Shows the broken Dockerfile. Identify all four issues: wrong base image tag, npm install before any COPY, commented-out COPY instructions, and shell-form CMD.

### Step 3: Check what application files exist

```bash
ls -la /opt/webapp/
```

**What this does:** Shows the files that need to be included in the Docker image — `app.js`, `package.json`, and the Dockerfile. These filenames must match exactly what the Dockerfile references.

### Step 4: Fix the Dockerfile

```bash
cat > /opt/webapp/Dockerfile << 'EOF'
FROM node:20-alpine

WORKDIR /app

COPY package.json .
RUN npm install

COPY app.js .

EXPOSE 8080
CMD ["npm", "start"]
EOF
```

**What this does:** Rewrites the Dockerfile with all four issues fixed:

- **`FROM node:20-alpine`** — uses a real, existing Node.js version (20 is an LTS release)
- **`COPY package.json .`** then **`RUN npm install`** — copies the dependency file first, THEN installs. This is also the optimal order for Docker layer caching: the npm install layer is cached and only re-runs when `package.json` changes
- **`COPY app.js .`** — copies the application source code after npm install. This means code changes don't invalidate the npm install cache layer
- **`CMD ["npm", "start"]`** — uses exec form (JSON array syntax), which runs npm directly as PID 1 instead of through a shell wrapper

### Step 5: Build the fixed image

```bash
docker build -t webapp:fixed /opt/webapp/
```

**What this does:** Builds the Docker image from the corrected Dockerfile. You should see each step complete successfully — pulling the base image, copying package.json, running npm install, copying app.js, and setting the CMD.

### Step 6: Run the container

```bash
docker run -d --name webapp webapp:fixed
```

**What this does:** Starts a container from the fixed image in detached mode. The `--name webapp` gives it the name the validation script expects.

### Step 7: Verify the application is working

```bash
docker exec webapp curl -s http://localhost:8080
```

**What this does:** Tests the application by making an HTTP request from inside the container. You should see `{"status":"ok","service":"webapp"}` — confirming the Node.js application is running correctly.

## Docker Lab vs Real Life

- **Node.js version selection:** In production, you'd pin to a specific LTS version like `node:20.11-alpine` (not just `node:20-alpine`) for maximum reproducibility. LTS versions receive security patches for years.
- **`.dockerignore` file:** In production, you'd create a `.dockerignore` file to exclude `node_modules/`, `.git/`, and other unnecessary files from the build context. This speeds up builds and prevents accidentally including large or sensitive files.
- **Multi-stage builds:** For production Node.js apps, you might use a multi-stage build — install dev dependencies and build in one stage, then copy only the production code and production dependencies to a slim final stage.
- **Non-root user:** Production Dockerfiles should add `USER node` (or another non-root user) to run the application without root privileges inside the container.
- **Health checks:** Production Dockerfiles include `HEALTHCHECK CMD curl -f http://localhost:8080/ || exit 1` so Docker and orchestrators can detect when the application is unhealthy.

## Key Concepts Learned

- **Base image tags must exist** — always verify the tag is valid. Use Docker Hub or `docker pull` to check. Stick to LTS versions for stability.
- **Instruction order matters** — you can't use a file before COPY'ing it into the image. Dependencies must be copied and installed before the application code.
- **The optimal Dockerfile pattern** for Node.js: `COPY package.json` → `RUN npm install` → `COPY . .`. This maximizes layer caching.
- **Exec form CMD is preferred** — `CMD ["npm", "start"]` (exec form) is better than `CMD npm start` (shell form) because it gives proper signal handling and doesn't create an unnecessary shell process.
- **Read error messages carefully** — Docker build errors tell you exactly what went wrong and on which line.

## Common Mistakes

- **Not reading the build output** — the error messages explicitly say what's wrong. Many people stare at the Dockerfile instead of reading what Docker is telling them.
- **Copying all files before npm install** — `COPY . .` then `RUN npm install` works, but any code change invalidates the npm install cache layer, making every build re-download dependencies. Copy `package.json` first.
- **Using `node:latest`** — the `latest` tag can change at any time, breaking your build unexpectedly. Always pin to a specific version.
- **Forgetting `WORKDIR`** — without `WORKDIR /app`, files are copied to the root filesystem, which is messy and can conflict with system files.
- **Not exposing the port** — forgetting `EXPOSE 8080` doesn't break the app, but it removes documentation and breaks some tools that use the metadata.
