# Solution Walkthrough — Lab 037: Registry Push/Pull

## TLDR

You've got a Docker image called `myapp:latest` sitting on your machine, and a private registry running on `localhost:5000` — but the registry is empty. The image was built with the wrong tag. Docker doesn't know where to push it unless the tag includes the registry address. You need to re-tag it as `localhost:5000/myapp:latest`, push it, then pull it back to prove it works.

Three commands. That's the fix. The rest of this walkthrough teaches you *why* it works.

---

## The Theory — How Docker Image Registries Actually Work

### What is a Docker Image?

When you run `docker build`, Docker reads your Dockerfile and creates an **image** — a read-only package containing your application code, its dependencies, and a minimal operating system. Think of it like a zip file that contains everything needed to run your app.

Each image is made up of **layers**. Every instruction in your Dockerfile (FROM, RUN, COPY, etc.) creates a new layer stacked on top of the previous one. Layers are cached and shared between images, which is why your second build is usually much faster than the first.

### What is a Registry?

A **registry** is just a server that stores and serves Docker images. That's it. It's a glorified file server with an API.

When you type `docker pull nginx`, Docker contacts a registry, downloads the image layers, and assembles them locally. When you type `docker push myapp`, Docker uploads your image layers to a registry.

There are three types you'll encounter:

**Docker Hub** — The default public registry. When you type `docker pull nginx`, Docker actually contacts `registry-1.docker.io` behind the scenes. It's free for public images, and it's where most open-source images live (nginx, python, redis, etc.).

**Private cloud registries** — Every cloud provider has one:
- AWS has **ECR** (Elastic Container Registry)
- Azure has **ACR** (Azure Container Registry)  
- GCP has **GCR** / Artifact Registry

These are what you'll use at work. At Tandem, your platform team almost certainly pushes images to ECR.

**Self-hosted registries** — You can run your own registry server. That's what's happening in this lab. The `registry:2` image from Docker Hub is a lightweight registry server. Run it on port 5000 and you've got your own private registry.

### The Critical Concept — Image Tags Are Addresses

This is the key thing this lab teaches you. A Docker image tag isn't just a name — **it's an address that tells Docker where to push the image**.

The full format of an image tag is:

```
[registry-address/][repository-name][:tag]
```

Let's break down some examples:

| What you type | What Docker actually sees |
|---|---|
| `nginx` | `docker.io/library/nginx:latest` |
| `nginx:1.25` | `docker.io/library/nginx:1.25` |
| `myapp:latest` | `docker.io/library/myapp:latest` |
| `localhost:5000/myapp:latest` | `localhost:5000/myapp:latest` |
| `123456789.dkr.ecr.eu-west-2.amazonaws.com/myapp:v1` | (exactly as typed — full ECR path) |

See the pattern? When there's no registry address in the tag, Docker assumes you mean Docker Hub (`docker.io`). When you want to push to a different registry, the tag **must** include the registry address as a prefix.

So when this lab built the image as `myapp:latest`, Docker would try to push it to Docker Hub — not to the local registry on port 5000. That's why the registry was empty.

### How Push and Pull Actually Work

When you run `docker push localhost:5000/myapp:latest`, here's what happens step by step:

1. Docker reads the tag and extracts the registry address: `localhost:5000`
2. Docker contacts that registry's API to check which layers it already has
3. For each layer the registry doesn't have, Docker uploads it (this is why you see individual "Pushed" lines)
4. Docker sends the **manifest** — a JSON file that describes how all the layers fit together to form the complete image
5. The registry stores everything and responds with a **digest** — a SHA256 hash that uniquely identifies this exact image

When you run `docker pull localhost:5000/myapp:latest`, the reverse happens — Docker contacts the registry, downloads any layers it doesn't already have locally, and assembles the image.

### The localhost Trap (What Caught You Out)

In this lab you ran `curl http://localhost:5000/v2/_catalog` from **inside** the lab container and got "Connection refused". But `docker push` worked fine from inside the same container. Why?

Two different things are happening:

**Docker commands** (push, pull, build, etc.) don't run inside your container. They talk to the **Docker daemon** running on the host machine via the Docker socket (`/var/run/docker.sock`), which was mounted into the lab container. So when Docker pushes to `localhost:5000`, it's the daemon on the **host** that makes the network connection — and from the host's perspective, the registry container is reachable on `localhost:5000`.

**curl** runs directly inside your container. From your container's perspective, `localhost` means "this container" — and there's nothing listening on port 5000 inside your container. The registry is a completely separate container with its own network namespace.

This is a fundamental Docker networking concept: **localhost inside a container refers to that container only, not the host machine**. To reach another container, you'd need to use the container's name on a shared Docker network, or the host's IP address.

### The Registry API

The Docker Registry exposes a simple HTTP API. The two most useful endpoints:

**List all images (the catalog):**
```
GET /v2/_catalog
→ {"repositories":["myapp","webapp","api"]}
```

**List all tags for an image:**
```
GET /v2/myapp/tags/list
→ {"name":"myapp","tags":["latest","v1","v2"]}
```

This is what the validation script checks — it curls the catalog endpoint to verify your image made it into the registry.

---

## Thought Process

An experienced engineer would approach this in order:

1. **Check what images exist locally** — `docker images` shows what's been built. You can see `myapp:latest` exists but there's no `localhost:5000/myapp` tag.
2. **Check what's in the registry** — `curl http://localhost:5000/v2/_catalog` (from the host, not inside a container) shows the registry is empty.
3. **Connect the dots** — Image exists locally but not in the registry. The tag doesn't include the registry address. That's the problem.

---

## Step-by-Step Solution

### Step 1: Check what images exist

```bash
docker images
```

**What this does:** Lists all Docker images stored locally on the machine. You'll see `myapp:latest` in the list — it's been built, but it's only stored locally.

### Step 2: Check what's in the registry

```bash
curl -s http://localhost:5000/v2/_catalog
```

**What this does:** Queries the registry's catalog API endpoint. `-s` means "silent" (hides the progress bar). This returns an empty repository list because nothing has been pushed yet.

**Important:** Run this from the host machine, not from inside a container. From inside a container, `localhost` refers to the container itself.

### Step 3: Tag the image for the local registry

```bash
docker tag myapp:latest localhost:5000/myapp:latest
```

**What this does:** Creates a new tag pointing to the same image. It does NOT copy the image — both tags reference identical image layers (you can verify this because they share the same Image ID in `docker images`).

Breaking it down:
- `docker tag` — the command to create a new tag
- `myapp:latest` — the source image (already exists)
- `localhost:5000/myapp:latest` — the new tag, which includes the registry address (`localhost:5000`) as a prefix

### Step 4: Push the image to the registry

```bash
docker push localhost:5000/myapp:latest
```

**What this does:** Uploads the image layers and manifest to the registry at `localhost:5000`. Docker reads the registry address from the tag prefix. You'll see each layer being pushed individually, followed by a digest (the SHA256 hash of the complete image).

### Step 5: Verify it's in the registry

```bash
curl -s http://localhost:5000/v2/_catalog
```

**What this does:** Same catalog query as before. This time it should return `{"repositories":["myapp"]}` confirming the image is stored in the registry.

### Step 6: Pull it back to verify the full round-trip

```bash
docker pull localhost:5000/myapp:latest
```

**What this does:** Downloads the image from the registry. Since the layers already exist locally, Docker will say "already exists" for each layer — but it still verifies the image is retrievable from the registry, which is the point.

---

## Docker Lab vs Real Life

- **Local registry vs ECR:** In this lab we used `localhost:5000` as the registry. In production at AWS, you'd use ECR with a tag like `123456789.dkr.ecr.eu-west-2.amazonaws.com/myapp:v1`. The push/pull mechanics are identical — only the address changes.
- **Authentication:** Our local registry has no authentication. Real registries require login first. For ECR: `aws ecr get-login-password | docker login --username AWS --password-stdin <ecr-url>`. For Docker Hub: `docker login`.
- **Image promotion:** In production, you'd typically push to a "dev" registry/repository, then promote (re-tag and push) to "staging" and "production" registries after testing.
- **CI/CD pipelines:** In real workflows, the push happens automatically in your CI/CD pipeline after a successful build and test, not manually from your terminal.

---

## Key Concepts Learned

- Docker image tags are addresses — the registry prefix tells Docker where to push
- `docker tag` creates a pointer, not a copy — both tags share the same layers
- A Docker registry is just an HTTP server with a standard API
- `localhost` means different things on the host vs inside a container
- Docker CLI commands go through the Docker socket to the daemon on the host
- `curl` from inside a container uses that container's own network stack
- The registry catalog API (`/v2/_catalog`) lets you verify what's stored

---

## Common Mistakes

- **Forgetting the registry prefix** — typing `docker push myapp:latest` tries to push to Docker Hub, not your local registry
- **Running curl from inside a container** — `localhost:5000` isn't reachable from inside another container's network namespace
- **Thinking docker tag copies the image** — it's just a label, the image data is shared
- **Not authenticating first** — in real environments, `docker push` will fail with "authentication required" if you haven't logged in
