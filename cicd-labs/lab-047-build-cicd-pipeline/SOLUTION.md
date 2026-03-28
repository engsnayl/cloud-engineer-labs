# Solution — Lab 047: Build a CI/CD Pipeline from Scratch

## Plain-English TLDR

You're building a complete CI/CD pipeline for a Node.js API. The pipeline runs in GitHub Actions and does five things in order: lint the code (catch style/syntax issues), run the tests (catch bugs), build a Docker image (package the app), deploy it (replace the running container), and smoke test it (confirm the new version is healthy). Lint and test run on every PR so broken code never reaches main. Deploy and smoke test only run when code is merged to main — because you don't deploy on a PR.

The key insight: a pipeline is just "automated things you'd do manually, in the right order, failing fast if any step goes wrong." If the linter fails, don't bother testing. If tests fail, don't bother building. If the build fails, don't deploy. If the deploy fails, don't pretend everything is fine.

---

## Step 1 — Understand What You're Working With

Before writing any pipeline, look at what the application already gives you.

```bash
ls app/
```

You'll see:
```
Dockerfile
.eslintrc.json
package.json
server.js
server.test.js
```

Check what scripts are already defined:

```bash
cat app/package.json
```

Look at the `scripts` section:

| Script | Command | What It Does |
|--------|---------|--------------|
| `npm run lint` | `eslint server.js` | Runs the linter — checks code for style and syntax issues |
| `npm test` | `jest --verbose` | Runs the unit tests — checks the API endpoints work correctly |
| `npm start` | `node server.js` | Starts the application |

**Why this matters:** You don't need to invent the lint or test commands — they're already wired up. Your pipeline just needs to call them.

---

## Step 2 — Create the Workflow Directory

GitHub Actions looks for workflow files in a specific location:

```bash
mkdir -p .github/workflows
```

| Component | Meaning |
|-----------|---------|
| `.github/` | Hidden directory that GitHub reads for repo configuration |
| `workflows/` | Subdirectory specifically for GitHub Actions workflow definitions |

Every `.yml` file in this directory becomes a pipeline that GitHub can run.

---

## Step 3 — Build the Workflow File

Create `.github/workflows/ci.yml`:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  IMAGE_NAME: api-service
  APP_PORT: 3000

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci
        working-directory: ./app

      - name: Run linter
        run: npm run lint
        working-directory: ./app

  test:
    name: Test
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci
        working-directory: ./app

      - name: Run tests
        run: npm test
        working-directory: ./app

  build:
    name: Build Docker Image
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t ${{ env.IMAGE_NAME }}:${{ github.sha }} ./app

      - name: Verify image exists
        run: docker images ${{ env.IMAGE_NAME }}:${{ github.sha }}

  deploy:
    name: Deploy
    needs: build
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy application
        run: |
          chmod +x deploy.sh
          ./deploy.sh ${{ github.sha }}

  smoke-test:
    name: Smoke Test
    needs: deploy
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Wait for application to start
        run: sleep 5

      - name: Health check
        run: |
          for i in 1 2 3 4 5; do
            STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:${{ env.APP_PORT }}/health || true)
            if [[ "$STATUS" == "200" ]]; then
              echo "Health check passed on attempt $i"
              exit 0
            fi
            echo "Attempt $i: got status $STATUS, retrying in 3s..."
            sleep 3
          done
          echo "Health check failed after 5 attempts"
          exit 1
```

### Breaking Down the Key Sections

**Triggers (`on:`):**

| Trigger | When It Fires |
|---------|--------------|
| `push: branches: [main]` | When code is merged/pushed directly to main |
| `pull_request: branches: [main]` | When a PR is opened or updated against main |

**Why both?** PRs get lint + test (catch problems early). Pushes to main get the full pipeline including deploy.

**Environment variables (`env:`):**

| Variable | Value | Why |
|----------|-------|-----|
| `IMAGE_NAME` | `api-service` | Single place to change the image name — not hardcoded in every step |
| `APP_PORT` | `3000` | Same — if the port changes, update it once |

**Job chaining (`needs:`):**

```
lint → test → build → deploy → smoke-test
```

Each job waits for the previous one to pass. If lint fails, nothing else runs. This is "fail fast" — don't waste time building an image if the code doesn't even pass the linter.

**Conditional execution (`if:`):**

```yaml
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

| Condition | What It Checks |
|-----------|---------------|
| `github.event_name == 'push'` | This was a push, not a PR event |
| `github.ref == 'refs/heads/main'` | The push was to the main branch |

Both conditions must be true. This means deploy and smoke test **only** run when code is merged to main — never on a PR.

**The health check retry loop:**

```bash
for i in 1 2 3 4 5; do
    STATUS=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000/health || true)
    ...
done
```

| Component | What It Does |
|-----------|-------------|
| `for i in 1 2 3 4 5` | Try up to 5 times |
| `curl -sf` | Silent mode, fail on HTTP errors |
| `-o /dev/null` | Discard response body — we only care about the status code |
| `-w "%{http_code}"` | Print just the HTTP status code |
| `\|\| true` | Don't let `curl` failing kill the whole script (we handle the failure ourselves) |
| `sleep 3` | Wait 3 seconds between retries — gives the container time to start |

---

## Step 4 — Create the Deploy Script

Create `deploy.sh` in the lab root:

```bash
#!/bin/bash
set -euo pipefail

# ---- Configuration ----
IMAGE_NAME="api-service"
CONTAINER_NAME="api-service"
PORT=3000
TAG="${1:?Usage: deploy.sh <image-tag>}"

echo "=== Deploying ${IMAGE_NAME}:${TAG} ==="

# Stop existing container (if running)
echo "Stopping existing container..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

# Start new container
echo "Starting new container with tag: ${TAG}"
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${PORT}:${PORT}" \
  "${IMAGE_NAME}:${TAG}"

# Wait for container to be healthy
echo "Waiting for container to start..."
for i in 1 2 3 4 5; do
  sleep 2
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/health" || true)
  if [[ "$STATUS" == "200" ]]; then
    echo "Deploy successful — container is healthy"
    exit 0
  fi
  echo "  Attempt ${i}: status ${STATUS}, retrying..."
done

echo "ERROR: Container failed health check after deploy"
echo "Rolling back — stopping unhealthy container"
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true
exit 1
```

Then make it executable:

```bash
chmod +x deploy.sh
```

### Breaking Down the Deploy Script

| Component | What It Does |
|-----------|-------------|
| `set -euo pipefail` | Exit on error (`-e`), error on undefined vars (`-u`), fail on pipe errors (`-o pipefail`) |
| `TAG="${1:?Usage: deploy.sh <image-tag>}"` | Takes the image tag as the first argument — if not provided, prints an error and exits |
| `docker stop ... \|\| true` | Stop old container — `\|\| true` prevents error if no container is running |
| `docker run -d` | Start new container in detached mode |
| Health check loop | Same retry pattern as the smoke test — wait for the app to respond |
| Rollback on failure | If the health check fails, stop the broken container so it's not left running in a bad state |

**Why the tag is a parameter, not hardcoded:** The pipeline passes `${{ github.sha }}` as the tag. This means every deploy is traceable to a specific commit. If something breaks, you know exactly which commit caused it. Using `latest` tells you nothing.

---

## Step 5 — Validate

```bash
bash validate.sh
```

You should see 10/10 checks pass:

```
  ✅  Workflow file exists at .github/workflows/ci.yml
  ✅  Workflow triggers on both push and pull_request
  ✅  Pipeline includes a lint step
  ✅  Pipeline includes a test step
  ✅  Pipeline builds Docker image tagged with git SHA
  ✅  Deploy stage is conditional (main branch only)
  ✅  Pipeline includes a post-deploy health/smoke check
  ✅  deploy.sh exists and is executable
  ✅  deploy.sh accepts a version parameter (not hardcoded latest)
  ✅  deploy.sh includes a health check after starting container
```

---

## How You'd Extend This for Production

The pipeline you've built covers the fundamentals. Here's what a production pipeline would add — and these are the things you should mention when an interviewer asks "what does your golden pipeline look like?"

### Quality Gates You'd Add

| Gate | What It Does | Where It Goes |
|------|-------------|---------------|
| **SAST scan** (e.g. Snyk, Trivy) | Scans code and dependencies for known vulnerabilities | After test, before build |
| **Container image scan** | Scans the built Docker image for CVEs | After build, before deploy |
| **Code coverage threshold** | Fails the pipeline if test coverage drops below a minimum (e.g. 80%) | In the test stage |
| **Manual approval gate** | Requires a human to click "approve" before production deploy | Between build and deploy |

### Environment Promotion

In a real setup, you wouldn't deploy straight to production:

```
PR → Lint + Test
Merge to main → Build → Deploy to staging → Integration tests → Manual approval → Deploy to production
```

Each environment (staging, production) has its own deploy step with its own health checks.

### Feature Flags

Feature flags let you deploy code that contains a new feature but keep the feature switched off until you're ready. This decouples **deployment** (shipping code) from **release** (enabling features for users). Tools like LaunchDarkly or even a simple environment variable toggle:

```javascript
if (process.env.FEATURE_NEW_DASHBOARD === 'true') {
  // show new dashboard
} else {
  // show old dashboard
}
```

**Why this matters:** You can deploy every day but release features on your own schedule. If a feature causes problems, you toggle the flag off — no rollback, no redeploy.

### Notifications

Production pipelines send notifications on failure — Slack messages, PagerDuty alerts, email. The team should know immediately if a deploy fails, not find out when customers complain.

---

## Interview Talking Points

When asked "walk me through your CI/CD pipeline," describe this lab:

1. "Code gets pushed to a PR. The pipeline runs lint and tests automatically — if either fails, the PR can't merge."
2. "Once merged to main, the pipeline builds a Docker image tagged with the commit SHA — never `latest`, because we need traceability."
3. "The deploy stage pulls the new image, stops the old container, and starts the new one."
4. "After deploy, a smoke test hits the health endpoint. If it fails after five retries, the pipeline fails and we know immediately."
5. "For production, I'd add a SAST scan, image scanning, environment promotion through staging, and a manual approval gate."

When asked "have you ever optimised a pipeline?":

- "I separated lint and test into independent jobs so they could theoretically run in parallel, reducing total pipeline time."
- "I used `npm ci` instead of `npm install` because it's faster and deterministic — it installs exactly what's in the lockfile."
- "I tagged images with the git SHA instead of `latest` so we always know exactly which commit is deployed."

---

## Cleanup and Reset

To reset this lab and start fresh:

```bash
rm -rf .github/
rm -f deploy.sh
```

This removes everything you created, leaving just the app files and lab infrastructure. You can re-run the lab from Step 1.
