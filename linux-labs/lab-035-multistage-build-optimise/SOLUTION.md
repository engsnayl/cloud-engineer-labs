# Solution Walkthrough — Multi-Stage Build Optimisation

## The Problem

The project has a working Dockerfile that builds and runs a Go web application — but the resulting image is **enormous** (~800MB–1GB). The reason is simple: the Dockerfile uses `FROM golang:1.21` as its base image, which includes the entire Go compiler, toolchain, standard library source code, and a full Debian operating system. All of that is needed to *compile* the application, but none of it is needed to *run* the compiled binary.

Go compiles down to a single static binary — the final executable has zero runtime dependencies. Shipping it inside a full Go development environment is like delivering a letter inside the entire postal truck. The image is bloated, slower to pull, consumes more storage, and has a much larger security attack surface (more packages installed = more potential vulnerabilities).

## Thought Process

When an experienced engineer sees a large container image, they immediately ask:

1. **What's actually needed at runtime?** For a Go app, only the compiled binary. For a Python app, the interpreter and packages. For a Java app, the JRE and JAR file. The build tools should not be in the final image.
2. **Can we use a multi-stage build?** Multi-stage builds are Docker's solution to this problem. You use one "stage" for building (with all the development tools) and a second stage for running (with only what's needed at runtime). Only the final stage becomes the image.
3. **What's the smallest possible base image?** `alpine:3.18` is a popular minimal Linux (~5MB). For Go specifically, you could even use `scratch` (a completely empty image) since Go binaries are statically linked.

## Step-by-Step Solution

### Step 1: Look at the current Dockerfile

```bash
cat /opt/webapp/Dockerfile
```

**What this does:** Shows the existing single-stage Dockerfile. It uses `golang:1.21` (a ~800MB image) for everything — both building and running. The compiled binary is tiny, but all the build tools stay in the image.

### Step 2: Check the current image size (if built)

```bash
docker build -t webapp:bloated /opt/webapp/
docker images webapp:bloated --format '{{.Size}}'
```

**What this does:** Builds the image with the current Dockerfile and shows its size. You'll see it's roughly 800MB–1GB. That's unacceptable for a simple web server.

### Step 3: Rewrite the Dockerfile with multi-stage build

```bash
cat > /opt/webapp/Dockerfile << 'EOF'
# Stage 1: Build — uses the full Go toolchain
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server main.go

# Stage 2: Run — uses a minimal base image
FROM alpine:3.18
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
EOF
```

**What this does:** Creates a two-stage Dockerfile:

**Stage 1 (`builder`):** Uses the full `golang:1.21` image to compile the application. `CGO_ENABLED=0` ensures the binary is statically linked (no dependency on C libraries), which means it can run on any Linux regardless of what libraries are installed. The `AS builder` gives this stage a name we can reference later.

**Stage 2 (final):** Starts fresh from `alpine:3.18` (a minimal ~5MB Linux distribution). The `COPY --from=builder` instruction copies just the compiled binary from Stage 1 into the clean Stage 2 image. All the Go toolchain, source code, and build artifacts from Stage 1 are discarded — they never appear in the final image.

The result: only the tiny binary (~7MB) and the Alpine base (~5MB) end up in the final image — roughly 12-15MB total, compared to ~800MB before.

### Step 4: Build the optimised image

```bash
docker build -t webapp:optimised /opt/webapp/
```

**What this does:** Builds the image using the new multi-stage Dockerfile. Docker executes both stages but only keeps the final stage as the image. You'll see it pull the Go image for building, compile the app, then switch to Alpine for the final image.

### Step 5: Check the new image size

```bash
docker images webapp:optimised --format 'Size: {{.Size}}'
```

**What this does:** Shows the size of the optimised image. It should be well under 100MB — typically around 12-15MB. That's a ~98% reduction from the original.

### Step 6: Run a container from the optimised image

```bash
docker run -d --name webapp-opt webapp:optimised
```

**What this does:** Starts a container from the optimised image, running in the background (`-d` for detached mode). The `--name webapp-opt` gives the container a name for easy reference.

### Step 7: Verify the application works

```bash
docker exec webapp-opt curl -s http://localhost:8080
```

**What this does:** Runs `curl` inside the container to test the web server. You should see "Hello from optimised container!" confirming that the application works correctly despite the dramatically smaller image.

## Docker Lab vs Real Life

- **Base image choices:** In this lab we use `alpine:3.18`. In production, you might use `distroless` images (Google's minimal images that contain only the runtime, no shell or package manager), or even `scratch` (completely empty) for Go binaries. Distroless is preferred in security-conscious environments because there's no shell for an attacker to use.
- **Image scanning:** In production, you'd scan images for vulnerabilities using tools like Trivy, Snyk, or Docker Scout. Smaller images have fewer packages, which means fewer potential vulnerabilities.
- **CI/CD builds:** Multi-stage builds are the standard pattern in CI/CD pipelines. The Dockerfile itself contains the complete build recipe — no need for external build scripts. The CI system just runs `docker build` and gets a production-ready image.
- **Build caching:** Docker caches each layer, so rebuilding after a code change only recompiles the Go binary, not re-downloads the base image. For faster builds in CI, you'd use `--cache-from` with a previously built image.
- **Non-Go languages:** Multi-stage builds work for any language. Java: build with Maven/Gradle, copy the JAR to a JRE image. Node.js: install dependencies and build, copy to a slimmer node image. Python: install packages, copy to a slim image.

## Key Concepts Learned

- **Multi-stage builds separate "build" from "run"** — use a full development image for compiling, then copy only the artifacts into a minimal runtime image
- **`COPY --from=builder` bridges stages** — this instruction copies files from a named stage into the current stage, leaving everything else behind
- **`CGO_ENABLED=0` creates static Go binaries** — this removes any dependency on C libraries, making the binary portable across any Linux base image
- **Smaller images are better in every way** — faster pulls, less storage, fewer vulnerabilities, quicker deployments, lower costs
- **Alpine Linux (~5MB) is the standard minimal base** — it provides a shell and package manager in a tiny footprint. `scratch` is even smaller (0MB) but provides nothing at all.

## Common Mistakes

- **Forgetting `CGO_ENABLED=0`** — without this, the Go binary may depend on C libraries that don't exist in Alpine, causing a confusing "not found" error at runtime even though the binary is right there.
- **Copying the entire /app directory instead of just the binary** — `COPY --from=builder /app/ /` would bring the source code and build artifacts into the final image, defeating the purpose.
- **Using `golang` as the runtime base** — the whole point is to NOT ship the Go toolchain. The final `FROM` should be a minimal image like `alpine` or `scratch`.
- **Not exposing the port** — forgetting `EXPOSE 8080` doesn't prevent the app from working, but it removes documentation about which port the container uses and breaks some orchestration tools.
- **Using `latest` tags in production** — `FROM golang:latest` can change unpredictably. Always pin to specific versions (`golang:1.21`, `alpine:3.18`) for reproducible builds.
