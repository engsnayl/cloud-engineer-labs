# Solution Walkthrough — Pipeline Secrets Injection

## The Problem

AWS credentials are not available during deployment, and worse, the current setup bakes secrets directly into the Docker image. There are **three bugs**:

1. **Secrets baked into the Dockerfile** — `ARG` and `ENV` instructions put `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `DATABASE_URL` directly into the image. Anyone who pulls the image can extract these credentials from the image layers.
2. **Secrets passed as Docker build args** — the GitHub Actions workflow passes secrets via `--build-arg`, which embeds them in the image build history. `docker history` reveals them in plain text.
3. **Wrong secret names** — the workflow uses `secrets.ACCESS_KEY` and `secrets.SECRET_KEY` instead of the standard `secrets.AWS_ACCESS_KEY_ID` and `secrets.AWS_SECRET_ACCESS_KEY`.

## Thought Process

When secrets aren't working in a CI/CD pipeline, an experienced engineer checks:

1. **Are secrets in the Dockerfile?** — credentials should NEVER appear in a Dockerfile as `ARG` or `ENV`. Image layers are permanent and visible to anyone with the image.
2. **Are secrets passed as build args?** — `--build-arg` values are stored in image metadata. Use `docker history` or `docker inspect` to see them. This is a security vulnerability.
3. **Are secret names correct?** — GitHub secrets are referenced by exact name. A typo means an empty string, not an error.
4. **When should secrets be injected?** — at runtime (environment variables in ECS task definitions, Kubernetes secrets, `docker run -e`), not at build time.

## Step-by-Step Solution

### Step 1: Remove secrets from the Dockerfile

Open the `Dockerfile` and remove all `ARG` and `ENV` lines that reference credentials.

```dockerfile
# BROKEN — secrets baked into the image!
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

ARG DATABASE_URL
ENV DATABASE_URL=$DATABASE_URL

ARG AWS_ACCESS_KEY_ID
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID

ARG AWS_SECRET_ACCESS_KEY
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

CMD ["node", "server.js"]

# FIXED — no secrets in the image
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "server.js"]
```

**What this does:** Removing the `ARG`/`ENV` lines ensures credentials are never embedded in the Docker image. The image now contains only application code. Credentials will be injected at runtime when the container starts, not at build time when the image is created.

### Step 2: Remove --build-arg from the workflow

Open `.github/workflows/deploy.yml` and remove the `--build-arg` flags that pass secrets to Docker build.

```yaml
# BROKEN — secrets visible in image layers
    steps:
      - name: Build Docker image
        run: |
          docker build \
            --build-arg AWS_ACCESS_KEY_ID=${{ secrets.ACCESS_KEY }} \
            --build-arg AWS_SECRET_ACCESS_KEY=${{ secrets.SECRET_KEY }} \
            --build-arg DATABASE_URL=${{ secrets.DATABASE_URL }} \
            -t myapp:latest .

# FIXED — no secrets in build command
    steps:
      - name: Build Docker image
        run: |
          docker build -t myapp:latest .
```

**What this does:** The Docker build command no longer passes any credentials. The image is built with only the application code. `--build-arg` values are stored in the image metadata — anyone with `docker history myapp:latest` or `docker inspect` could see the credentials in plain text.

### Step 3: Fix the secret names in the workflow

Use the standard AWS credential names when referencing GitHub secrets for deployment.

```yaml
# BROKEN — wrong secret names
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.ACCESS_KEY }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.SECRET_KEY }}

# FIXED — standard secret names
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**What this does:** GitHub secrets are referenced by their exact configured name. The AWS CLI and SDKs expect `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as environment variable names. Using the wrong names (`ACCESS_KEY`, `SECRET_KEY`) results in empty values, and AWS commands fail with "Unable to locate credentials."

### Step 4: Inject secrets at runtime instead

In the deploy step, pass credentials to the running container, not the build.

```yaml
      - name: Deploy
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          docker build -t myapp:latest .
          # Push to ECR, then deploy via ECS/EKS
          # Credentials are in the DEPLOYMENT environment, not the image
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO
          docker push $ECR_REPO/myapp:latest
```

**What this does:** AWS credentials are available as environment variables during the deploy step (for pushing to ECR, updating ECS, etc.) but are never embedded in the Docker image. The running container receives its credentials via the ECS task definition, Kubernetes secrets, or `docker run -e` at startup time.

### Step 5: Validate

```bash
# Check no secrets in Dockerfile
grep -i "AWS_ACCESS_KEY\|AWS_SECRET\|DATABASE_URL" Dockerfile
# Should return nothing

# Check no --build-arg with secrets in workflow
grep -i "build-arg.*secret\|build-arg.*KEY\|build-arg.*DATABASE" .github/workflows/deploy.yml
# Should return nothing
```

## Docker Lab vs Real Life

- **IAM roles instead of access keys:** In production AWS environments, use IAM roles for ECS tasks (`task_role_arn`) or EC2 instance profiles. The application never sees credentials — AWS SDKs automatically use the role. No environment variables needed.
- **AWS Secrets Manager:** For database URLs and API keys, store them in AWS Secrets Manager and reference them in ECS task definitions using `valueFrom`. The container receives the secret at startup without it touching CI/CD.
- **OIDC for GitHub Actions:** Instead of storing AWS access keys as GitHub secrets, configure OIDC federation. GitHub Actions assumes an IAM role directly — no long-lived credentials to manage or rotate.
- **Docker multi-stage builds:** If you need build-time secrets (e.g., private npm registry tokens), use Docker BuildKit secrets (`--mount=type=secret`) which are never stored in image layers.
- **Image scanning:** Production pipelines run Trivy or Snyk to scan Docker images for leaked secrets and vulnerabilities before pushing to the registry.

## Key Concepts Learned

- **Never bake secrets into Docker images** — `ARG` and `ENV` values are stored in image layers permanently. Anyone with the image can extract them.
- **`--build-arg` values are visible in image history** — `docker history` shows all build arguments. This is not a secret storage mechanism.
- **Inject secrets at runtime, not build time** — use ECS task definitions, Kubernetes secrets, or `docker run -e` to provide credentials when the container starts.
- **Use exact secret names** — GitHub secrets are referenced by their configured name. Typos result in empty strings, not errors.
- **IAM roles are the gold standard** — in AWS, IAM roles for services (ECS tasks, EC2 instances, Lambda) eliminate the need for access keys entirely.

## Common Mistakes

- **Leaving `ARG`/`ENV` for credentials in Dockerfile** — this is the #1 Docker security mistake. The credentials are permanently in every image layer.
- **Using `--build-arg` for secrets** — build args are metadata, not secrets. Use Docker BuildKit `--secret` mount if you truly need build-time secrets.
- **Wrong secret names in GitHub Actions** — `secrets.ACCESS_KEY` vs `secrets.AWS_ACCESS_KEY_ID`. There's no error — you just get an empty string.
- **Committing `.env` files** — similar to the Dockerfile issue. If `.env` is in the repo, credentials are in git history forever. Add `.env` to `.gitignore`.
- **Not rotating compromised credentials** — if secrets were ever baked into an image, they must be rotated immediately. The old credentials are compromised even if you rebuild the image.
