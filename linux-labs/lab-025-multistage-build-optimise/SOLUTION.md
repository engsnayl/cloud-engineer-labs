# Solution Walkthrough — Lab 025: Multi-Stage Build Optimisation

---

## TLDR — What's Wrong and How to Fix It

**The problem in plain English:** You've got a working Dockerfile that builds a Go web app, but the resulting image is massive (~1.14GB). Why? Because the image includes the entire Go compiler, its full source tree, and a complete Debian operating system — all stuff that was needed to *compile* the code but is completely unnecessary to *run* it. A Go app compiles down to a single binary file. Shipping that binary inside a full development environment is like posting a letter and sending the entire Royal Mail van with it.

**The fix in plain English:** Use a **multi-stage build**. This means your Dockerfile has two sections (stages). Stage 1 uses the big Go image to compile your code. Stage 2 starts fresh with a tiny Alpine Linux image (~5MB) and copies *only* the compiled binary across from Stage 1. Everything else from Stage 1 gets thrown away. Your final image goes from ~1.14GB down to ~13MB. Same app, ~99% smaller.

---

## The Problem (Detail)

The project has a working Dockerfile that builds and runs a Go web application — but the resulting image is enormous (~1.14GB). The Dockerfile uses `FROM golang:1.21` as its base image, which includes the entire Go compiler, toolchain, standard library source code, and a full Debian operating system. All of that is needed to *compile* the application, but none of it is needed to *run* the compiled binary.

Go compiles down to a single static binary — the final executable has zero runtime dependencies. The image is bloated, slower to pull, consumes more storage, and has a much larger security attack surface (more packages installed = more potential vulnerabilities).

---

## Thought Process

When an experienced engineer sees a large container image, they immediately ask:

1. **What's actually needed at runtime?** For a Go app, only the compiled binary. For a Python app, the interpreter and packages. For a Java app, the JRE and JAR file. The build tools should not be in the final image.
2. **Can we use a multi-stage build?** Multi-stage builds are Docker's solution to this problem. You use one "stage" for building (with all the development tools) and a second stage for running (with only what's needed at runtime). Only the final stage becomes the image.
3. **What's the smallest possible base image?** `alpine:3.18` is a popular minimal Linux (~5MB). For Go specifically, you could even use `scratch` (a completely empty image) since Go binaries are statically linked.

---

## Step-by-Step Solution

### Step 1: Find the Dockerfile

Before you can fix anything, you need to find where the application and its Dockerfile live. There's no fixed standard for where apps are placed — it depends on whoever set up the environment.

```bash
find / -name Dockerfile 2>/dev/null
```

**Command breakdown:**
- `find` — searches for files and directories across the filesystem
- `/` — start searching from the root (top) of the filesystem, i.e. search everywhere
- `-name Dockerfile` — look for files with the exact name `Dockerfile`
- `2>/dev/null` — redirects error messages (like "permission denied" on directories you can't access) to nowhere, so your output stays clean

**What you'll see:**
```
/usr/share/go-1.18/src/crypto/elliptic/internal/fiat/Dockerfile
/opt/webapp/Dockerfile
```

**Important:** You'll get two results here. The first one at `/usr/share/go-1.18/src/...` is **not yours** — it's a Dockerfile that came bundled inside the Go installation's own source code. Go ships with its entire source tree, including internal build files. You can ignore that one completely. The fact that an entire Go source tree (with its own Dockerfiles and tooling) is sitting inside the image is actually part of the problem — it's exactly the kind of unnecessary baggage you're about to eliminate.

The one you care about is `/opt/webapp/Dockerfile` — that's the lab's application Dockerfile.

---

### Step 2: Read the current Dockerfile

```bash
cat /opt/webapp/Dockerfile
```

**Command breakdown:**
- `cat` — prints the contents of a file to the terminal (short for "concatenate")
- `/opt/webapp/Dockerfile` — the path to the file we want to read

**What you'll see (the problematic Dockerfile):**

```dockerfile
FROM golang:1.21
WORKDIR /app
COPY . .
RUN go build -o server main.go
EXPOSE 8080
CMD ["/app/server"]
```

**Why this Dockerfile is a problem — line by line:**

- `FROM golang:1.21` — This is where the bloat starts. This base image is ~800MB. It includes the full Go compiler, the entire Go standard library source code (with its own Dockerfiles inside it), build tools, and a complete Debian operating system. All of this is needed to run the `go build` command — but once the binary is compiled, none of it is needed anymore. Yet it all stays in the final image.
- `WORKDIR /app` — Sets the working directory. This is fine, no issue here.
- `COPY . .` — Copies all the application source code into the image. Again needed for the build, but the source code serves no purpose once the binary is compiled. It stays in the final image anyway.
- `RUN go build -o server main.go` — Compiles the Go source code into a binary called `server`. This is the only step that actually needs the Go toolchain. After this runs, the binary is ~7MB — but the 800MB+ of build tools and OS are still sitting underneath it.
- `EXPOSE 8080` — Documents the port. Fine.
- `CMD ["/app/server"]` — Runs the binary. Fine.

**The core issue:** This is a single-stage build. Everything that was needed to *build* the binary stays in the image that will *run* the binary. There's no separation between the build environment and the runtime environment. The compiled binary is ~7MB. The image carrying it is ~1.14GB. That's ~99% waste.

---

### Step 3: Check the current image size

```bash
docker images
```

**Command breakdown:**
- `docker images` — lists all Docker images stored on the system, showing their name, tag, ID, age, and size

Or for a more targeted check:

```bash
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep webapp
```

**Command breakdown:**
- `--format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'` — uses Go template syntax to show only the columns we care about (name, tag, size). `\t` adds tab spacing between columns
- `| grep webapp` — pipes the output through `grep` to filter for lines containing "webapp"

**What you'll see:** The image is roughly 1.14GB. For a simple web server that responds with a single line of text, that's absurdly large.

---

### Step 4: Rewrite the Dockerfile with multi-stage build

```bash
cat > /opt/webapp/Dockerfile << 'EOF'
# Stage 1: Build — uses the full Go toolchain
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server main.go

# Stage 2: Run — uses a minimal base image
FROM alpine:3.18
RUN apk add --no-cache curl
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
EOF
```

**Command breakdown (the shell part):**
- `cat >` — redirects output into a file (overwrites whatever was there before)
- `<< 'EOF'` — a "heredoc". Everything between this line and the closing `EOF` gets written into the file. The quotes around `'EOF'` stop the shell from interpreting any special characters inside the content

**How the new Dockerfile solves the problem — line by line:**

**Stage 1 (the build stage):**
- `FROM golang:1.21 AS builder` — still starts from the full Go image because we need the compiler. But `AS builder` gives this stage a name so we can reference it from Stage 2. The critical difference: this stage will be thrown away after we extract what we need from it.
- `WORKDIR /app` — sets the working directory inside the container to `/app`
- `COPY . .` — copies the source code in, same as before. But this time the source code only exists in the temporary build stage, not in the final image.
- `RUN CGO_ENABLED=0 go build -o server main.go` — compiles the binary, but with one important addition:
  - `CGO_ENABLED=0` — an environment variable that tells Go to NOT use any C libraries. This makes the binary fully self-contained (statically linked), so it can run on any Linux without needing specific libraries installed. Without this, the binary might depend on C libraries that exist in Debian but don't exist in Alpine, causing a confusing "not found" error at runtime.
  - `go build` — the Go compiler command
  - `-o server` — names the output binary `server`
  - `main.go` — the source file to compile

**Stage 2 (the runtime stage) — this is what solves the problem:**
- `FROM alpine:3.18` — starts a **completely fresh image** from Alpine Linux (~5MB). This is NOT layered on top of Stage 1 — it's a clean slate. The entire Go toolchain, Debian OS, source code, and build artifacts from Stage 1 are gone. This single line is what eliminates ~99% of the bloat.
- `RUN apk add --no-cache curl` — installs curl into the Alpine image. Alpine is so minimal it doesn't include curl by default. We need it for health checks and testing. `apk` is Alpine's package manager (like `apt` on Debian). `--no-cache` tells it not to store the package index locally, keeping the image small.
- `COPY --from=builder /app/server /server` — this is the key instruction that bridges the two stages:
  - `--from=builder` — reach back into the `builder` stage (Stage 1)
  - `/app/server` — grab the compiled binary from that stage
  - `/server` — place it at the root of this new image
  - Everything else from Stage 1 (Go compiler, source code, Debian OS, Go's own source tree with its Dockerfiles) is left behind permanently
- `EXPOSE 8080` — documents that the container listens on port 8080. This doesn't actually open the port — it's metadata for other tools and humans.
- `CMD ["/server"]` — the default command when the container starts. Runs the binary we copied in.

**The result:** The final image contains only Alpine (~5MB), curl (~a few MB), and the compiled binary (~7MB). Roughly 13MB total instead of 1.14GB.

---

### Step 5: Build the optimised image

```bash
docker build -t webapp:optimised /opt/webapp/
```

**Command breakdown:**
- `docker build` — tells Docker to build an image from a Dockerfile
- `-t webapp:optimised` — tags (names) the image. `webapp` is the image name, `optimised` is the tag/version label
- `/opt/webapp/` — the build context (the directory containing the Dockerfile and source code). Docker sends everything in this directory to the build process

Docker executes both stages but only keeps the final stage as the image. You'll see it pull the Go image for building, compile the app, then switch to Alpine for the final image.

---

### Step 6: Check the new image size

```bash
docker images webapp:optimised --format 'Size: {{.Size}}'
```

**Command breakdown:**
- `docker images` — lists Docker images on the system
- `webapp:optimised` — filters to show only this specific image
- `--format 'Size: {{.Size}}'` — uses Go template syntax to display only the size field, with the literal text "Size: " before the actual value for readability

**What you'll see:** Around 13MB. That's down from 1.14GB — a ~99% reduction.

---

### Step 7: Run a container from the optimised image

```bash
docker run -d --name webapp-opt -p 8080:8080 webapp:optimised
```

**Command breakdown:**
- `docker run` — creates and starts a new container
- `-d` — "detached" mode. Runs the container in the background so you get your terminal back
- `--name webapp-opt` — gives the container a human-friendly name instead of a random one like `jolly_curie`
- `-p 8080:8080` — publishes port 8080. The format is `host_port:container_port`. This maps port 8080 on your host machine to port 8080 inside the container, making the app accessible from outside the container
- `webapp:optimised` — the image to create the container from

---

### Step 8: Verify the application works

```bash
docker exec webapp-opt curl -s http://localhost:8080
```

**Command breakdown:**
- `docker exec` — runs a command inside an already-running container
- `webapp-opt` — the name of the container to run the command in
- `curl` — a command-line tool for making HTTP requests (available because we installed it in the Dockerfile)
- `-s` — "silent" mode. Suppresses the progress bar and other noise, giving you just the response
- `http://localhost:8080` — the URL to request. `localhost` works here because we're running curl *inside* the container, where the web server is listening

**What you'll see:** "Hello from optimised container!" — confirmation the app works in the smaller image.

**Note:** If you ever work with an Alpine image that doesn't have curl installed, you can use `wget` instead, which Alpine includes by default:
```bash
docker exec webapp-opt wget -qO- http://localhost:8080
```
- `-q` — quiet mode (like curl's `-s`)
- `-O-` — output to stdout (the dash means "print to screen" instead of saving to a file)

---

## Docker Lab vs Real Life

- **Base image choices:** In this lab we use `alpine:3.18`. In production, you might use `distroless` images (Google's minimal images that contain only the runtime, no shell or package manager), or even `scratch` (completely empty) for Go binaries. Distroless is preferred in security-conscious environments because there's no shell for an attacker to use.
- **Image scanning:** In production, you'd scan images for vulnerabilities using tools like Trivy, Snyk, or Docker Scout. Smaller images have fewer packages, which means fewer potential vulnerabilities.
- **CI/CD builds:** Multi-stage builds are the standard pattern in CI/CD pipelines. The Dockerfile itself contains the complete build recipe — no need for external build scripts. The CI system just runs `docker build` and gets a production-ready image.
- **Build caching:** Docker caches each layer, so rebuilding after a code change only recompiles the Go binary, not re-downloads the base image. For faster builds in CI, you'd use `--cache-from` with a previously built image.
- **Non-Go languages:** Multi-stage builds work for any language. Java: build with Maven/Gradle, copy the JAR to a JRE image. Node.js: install dependencies and build, copy to a slimmer node image. Python: install packages, copy to a slim image.
- **Image housekeeping:** Docker doesn't clean up after itself. Over time, old images from previous builds accumulate and eat disk space. Run `docker system df` to see total usage, `docker image prune` to remove dangling (untagged) images, or `docker system prune -a` to remove everything not currently in use. On a lab machine or CI runner, regular pruning is essential.

---

## Key Concepts Learned

- **Multi-stage builds separate "build" from "run"** — use a full development image for compiling, then copy only the artifacts into a minimal runtime image
- **`COPY --from=builder` bridges stages** — this instruction copies files from a named stage into the current stage, leaving everything else behind
- **`CGO_ENABLED=0` creates static Go binaries** — this removes any dependency on C libraries, making the binary portable across any Linux base image
- **Smaller images are better in every way** — faster pulls, less storage, fewer vulnerabilities, quicker deployments, lower costs
- **Alpine Linux (~5MB) is the standard minimal base** — it provides a shell and package manager in a tiny footprint, but is so minimal that common tools like `curl` need to be explicitly installed. `scratch` is even smaller (0MB) but provides nothing at all
- **`find / -name Dockerfile`** — a practical way to locate files when you don't know where things are placed. Not every environment follows the same directory conventions

---

## Common Mistakes

- **Forgetting `CGO_ENABLED=0`** — without this, the Go binary may depend on C libraries that don't exist in Alpine, causing a confusing "not found" error at runtime even though the binary is right there
- **Copying the entire /app directory instead of just the binary** — `COPY --from=builder /app/ /` would bring the source code and build artifacts into the final image, defeating the purpose
- **Using `golang` as the runtime base** — the whole point is to NOT ship the Go toolchain. The final `FROM` should be a minimal image like `alpine` or `scratch`
- **Assuming Alpine has common tools** — Alpine is deliberately minimal. Tools like `curl`, `bash`, and `git` are not included by default. If your app or health checks need them, add them with `apk add --no-cache`
- **Not publishing ports** — running a container without `-p 8080:8080` means the app is only reachable from inside the container. External tools, validation scripts, and other services won't be able to connect
- **Not exposing the port in the Dockerfile** — forgetting `EXPOSE 8080` doesn't prevent the app from working, but it removes documentation about which port the container uses and breaks some orchestration tools
- **Using `latest` tags in production** — `FROM golang:latest` can change unpredictably. Always pin to specific versions (`golang:1.21`, `alpine:3.18`) for reproducible builds
- **Letting old images accumulate** — Docker doesn't clean up automatically. Use `docker system prune -a` periodically to reclaim disk space, especially on machines with limited storage
