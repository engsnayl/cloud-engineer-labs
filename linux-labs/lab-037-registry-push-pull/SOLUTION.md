# Solution Walkthrough — Registry Push/Pull

## The Problem

A Docker image called `myapp:latest` has been built and exists locally, but it can't be pushed to the local Docker registry running on `localhost:5000`. The issue is straightforward: **the image is tagged incorrectly**.

Docker uses the image tag to determine *where* to push an image. When you run `docker push myapp:latest`, Docker tries to push to Docker Hub (the default public registry). To push to a specific registry, the image name must be prefixed with the registry address — in this case, `localhost:5000/myapp:latest`.

Think of it like a mailing address: `myapp:latest` is just a name with no address, so Docker sends it to the default location (Docker Hub). `localhost:5000/myapp:latest` includes the full address, telling Docker exactly which registry to use.

## Thought Process

When you can't push an image to a registry, an experienced engineer checks:

1. **Is the registry running?** Check with `curl http://localhost:5000/v2/_catalog` — this is the registry's API endpoint that lists all stored images.
2. **Is the image tagged correctly?** `docker images | grep myapp` shows how the image is tagged. If the tag doesn't include the registry hostname, Docker will try to push to Docker Hub.
3. **Retag and push** — use `docker tag` to add the registry prefix, then `docker push`.

## Step-by-Step Solution

### Step 1: Verify the local registry is running

```bash
curl -s http://localhost:5000/v2/_catalog
```

**What this does:** Queries the Docker Registry's HTTP API to see what images are stored. The `v2/_catalog` endpoint lists all repositories in the registry. You'll see `{"repositories":[]}` — the registry is running but empty. No images have been pushed to it yet.

### Step 2: Check the current image tags

```bash
docker images | grep myapp
```

**What this does:** Lists all local Docker images matching "myapp." You'll see `myapp:latest` — but notice there's no `localhost:5000/` prefix. This means Docker doesn't know this image should go to the local registry.

### Step 3: Tag the image for the local registry

```bash
docker tag myapp:latest localhost:5000/myapp:latest
```

**What this does:** Creates a new tag that points to the same image. `docker tag` doesn't copy the image — it just adds another name (like a symbolic link). The new tag `localhost:5000/myapp:latest` tells Docker that this image belongs to the registry at `localhost:5000`.

The tag format is: `registry-host:port/repository:version`
- `localhost:5000` — the registry address
- `myapp` — the repository name
- `latest` — the version tag

### Step 4: Push the image to the local registry

```bash
docker push localhost:5000/myapp:latest
```

**What this does:** Uploads the image layers to the local registry. Docker reads the tag, sees `localhost:5000`, and pushes to that registry instead of Docker Hub. You'll see each layer being pushed, and a digest returned on success.

### Step 5: Verify the image is in the registry

```bash
curl -s http://localhost:5000/v2/_catalog
```

**What this does:** Queries the registry catalog again. This time you should see `{"repositories":["myapp"]}` — confirming the image was successfully stored in the registry.

### Step 6: Test pulling the image (to prove it works)

```bash
docker rmi localhost:5000/myapp:latest
docker pull localhost:5000/myapp:latest
```

**What this does:** First, we remove the local copy of the registry-tagged image (`docker rmi` removes an image tag). Then we pull it back from the registry. This round-trip proves the registry is fully functional — you can both push and pull images.

### Step 7: Verify the pulled image exists

```bash
docker image inspect localhost:5000/myapp:latest > /dev/null && echo "Image exists"
```

**What this does:** Confirms the image was successfully pulled from the registry and exists locally. `docker image inspect` returns detailed metadata about an image — if the image doesn't exist, it returns an error.

## Docker Lab vs Real Life

- **Local vs. remote registries:** In this lab, the registry runs on `localhost:5000`. In production, you'd use a hosted registry like Docker Hub, Amazon ECR (`123456789.dkr.ecr.us-east-1.amazonaws.com`), Google Artifact Registry (`us-docker.pkg.dev`), Azure Container Registry (`myregistry.azurecr.io`), or GitHub Container Registry (`ghcr.io`).
- **Authentication:** This lab uses an unauthenticated registry. In production, registries require authentication. For Docker Hub: `docker login`. For AWS ECR: `aws ecr get-login-password | docker login --username AWS --password-stdin <registry-url>`.
- **HTTPS:** This lab uses HTTP (unencrypted). Production registries always use HTTPS. If you must use HTTP (for testing), you need to configure Docker to allow "insecure registries" in `/etc/docker/daemon.json`.
- **Image tags in CI/CD:** In production CI/CD pipelines, images are automatically built, tagged with the git commit SHA or version number (not just `latest`), pushed to the registry, and then deployed. The tag acts as an immutable reference to a specific build.
- **Image scanning:** Production registries often include vulnerability scanning. AWS ECR, Docker Hub, and others can automatically scan images for known vulnerabilities when they're pushed.

## Key Concepts Learned

- **Docker image tags encode the destination registry** — the format `registry:port/name:version` tells Docker where to push. Without a registry prefix, Docker defaults to Docker Hub.
- **`docker tag` adds a new name to an existing image** — it doesn't copy data, just creates an alias. An image can have multiple tags pointing to it.
- **`docker push` reads the tag to determine the target** — the tag's registry prefix is what controls where the image goes
- **The Registry HTTP API** is available at `/v2/_catalog` for listing images and `/v2/<name>/tags/list` for listing tags. This is useful for scripting and verification.
- **Private registries enable self-hosted image storage** — useful for private images, faster pulls (local network), and meeting compliance requirements about where images are stored

## Common Mistakes

- **Trying to push without the registry prefix** — `docker push myapp:latest` tries to push to Docker Hub, which will fail if you're not authenticated or don't have permission. The image must be tagged with `localhost:5000/myapp:latest` first.
- **Forgetting to start the registry** — the registry is a container itself (`registry:2`). If it's not running, pushes and pulls will fail with a "connection refused" error.
- **Confusing `docker tag` with `docker rename`** — `docker tag` creates an additional tag, it doesn't remove the original. Both `myapp:latest` and `localhost:5000/myapp:latest` exist after tagging.
- **Using `latest` tag exclusively** — in production, `latest` is ambiguous and can change at any time. Always tag images with specific versions (e.g., `v1.2.3` or a git commit SHA) for reproducible deployments.
- **Not configuring insecure registries for HTTP** — Docker defaults to HTTPS. If your registry is HTTP-only (like `localhost:5000` in this lab), you need to add it to Docker's insecure-registries list, or you'll get TLS errors. Localhost is a special exception that Docker allows by default.
