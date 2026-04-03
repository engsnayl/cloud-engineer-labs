# Solution — Lab 047: Build a CI/CD Pipeline from Scratch

## Plain-English TLDR

You've joined a team where developers deploy by SSH-ing into a server and running Docker commands by hand. Someone broke production last Friday by typing the wrong tag name. Your tech lead has asked you to automate this properly.

You're going to build a pipeline — a set of automated steps that run every time code is pushed to the repo. The pipeline does five things in order: check the code for style issues (lint), run the tests (catch bugs), build a Docker image (package the app), deploy it (swap the old container for the new one), and smoke test it (hit the health endpoint to confirm it's alive).

The key idea: a pipeline is just "automated things you'd do manually, in the right order, failing fast if any step goes wrong." If the linter fails, don't bother testing. If tests fail, don't bother building. If the build fails, don't deploy. If the deploy fails, don't pretend everything is fine.

There are no bugs to find here. This is a build lab — you're creating from zero.

---

## Your Commented Reference Files

During your first run-through of this lab, you created heavily commented versions of both the workflow file and deploy script. These are saved at:

```
~/cloud-engineer-labs/cicd-labs/reference/lab-047/ci.yml
~/cloud-engineer-labs/cicd-labs/reference/lab-047/deploy.sh
```

These won't interfere with the lab. If you want to refer back to them:

```bash
cat ~/cloud-engineer-labs/cicd-labs/reference/lab-047/ci.yml
cat ~/cloud-engineer-labs/cicd-labs/reference/lab-047/deploy.sh
```

---

## Step 1 — Arrive at the Scene and Understand What You've Got

You've been given a ticket:

> **TICKET-CICD-047**: Build a CI/CD pipeline for the API service. Must include: lint, test, Docker build, deploy, and a post-deploy health check. No more manual deploys. Pipeline should fail fast if code quality checks don't pass.

Before you write a single line of pipeline config, you need to understand the application. You can't automate something you don't understand.

### 1a — What files exist?

```bash
ls app/
```

You'll see:

```
Dockerfile  .eslintrc.json  package.json  server.js  server.test.js
```

**How would I know what these are?** Let's check the most important one first — the file that describes the project:

```bash
cat app/package.json
```

Look at the `scripts` section:

```json
"scripts": {
    "start": "node server.js",
    "test": "jest --verbose",
    "lint": "eslint server.js"
}
```

This tells you the app already has lint and test commands wired up. You don't need to invent them — your pipeline just needs to call them.

### What is package.json?

`package.json` is the identity card for a Node.js application. Every Node.js project has one — the name is mandatory and `npm` won't look for anything other file. It declares three things: what the app is called, what other software it depends on (dependencies), and what commands are available to manage it (scripts).

When you run `npm ci` or `npm install`, Node reads this file to know what packages to download. When you run `npm test`, it looks in the `scripts` section to find out what command that actually maps to. So `npm test` doesn't magically know how to test your app — it reads the scripts section, sees `"test": "jest --verbose"`, and runs that command. It's just an alias.

Different languages have their own equivalent of `package.json`:

| Language | Dependency File |
|----------|----------------|
| Node.js | `package.json` |
| Python | `requirements.txt` or `pyproject.toml` |
| Java | `pom.xml` (Maven) or `build.gradle` (Gradle) |
| Ruby | `Gemfile` |
| Go | `go.mod` |

They all do the same fundamental thing — declare "here are the packages this project depends on."

### What does "lint" mean?

Linting is an automated code quality check. A linter reads through your code and flags things like unused variables, missing semicolons, inconsistent formatting, or patterns that commonly lead to bugs. It doesn't run the code — it just reads it and says "this looks wrong" or "this doesn't follow the rules."

The name comes from actual lint — the fluff you pick off clothes. A linter picks the fluff off your code.

When `npm run lint` executes, it runs `eslint server.js`. ESLint then reads `.eslintrc.json` to find out what rules to check against, and scans `server.js` against those rules. So `.eslintrc.json` is the rulebook, `server.js` is the thing being checked, and ESLint is the tool doing the checking.

### 1b — What does the app actually do?

```bash
cat app/server.js
```

Key things to note for your pipeline:

- The app listens on port 3000 (or whatever `PORT` is set to)
- There's a `/health` endpoint that returns HTTP 200 — this is what your smoke test will hit
- There are API endpoints (`/api/items`) but those aren't relevant to the pipeline

### 1c — How does the Docker image get built?

```bash
cat app/Dockerfile
```

Key things to note:

- It uses `npm ci --only=production` — installs only runtime dependencies, not dev tools like the linter or test framework. Those are only needed in the pipeline, not in the deployed container
- `EXPOSE 3000` — the app runs on port 3000
- It has a built-in `HEALTHCHECK` that hits `/health`

**Why does this matter?** Now you know the port your deploy script needs to map, and the endpoint your smoke test needs to hit. You gathered this from reading the code — not from being told.

---

## Step 2 — Plan the Pipeline Before Writing It

Now you know what the app looks like, think about what the pipeline needs to do. The ticket says: lint, test, build, deploy, smoke test. Think about the logical order:

1. **Lint first** — if the code has style problems, catch them before doing anything else
2. **Test second** — if lint passes, check the code actually works
3. **Build third** — if tests pass, package it into a Docker image
4. **Deploy fourth** — if the build succeeds, swap the running container
5. **Smoke test last** — after deploy, confirm the new version is healthy

Each step depends on the previous one succeeding. If lint fails, there's no point testing. If tests fail, there's no point building. This is "fail fast."

There's one more requirement: deploy and smoke test should only run when code is merged to main. When someone opens a PR, you want lint + test + build (to validate the code), but you don't want to deploy unreviewed code.

Now you're ready to build.

---

## Step 3 — Create the Workflow Directory

GitHub Actions looks for workflow files in one specific location:

```bash
mkdir -p .github/workflows
```

| Component | What It Means |
|-----------|--------------|
| `mkdir` | Create a directory |
| `-p` | Create parent directories too — makes `.github/` first, then `workflows/` inside it |
| `.github/` | Hidden directory that GitHub reads for repo configuration |
| `workflows/` | Subdirectory specifically for GitHub Actions workflow definitions |

Every `.yml` file in `.github/workflows/` becomes a pipeline that GitHub can run. It won't look anywhere else.

---

## Step 4 — Build the Workflow File

Create `.github/workflows/ci.yml`. We'll build it section by section.

### 4a — Name and Triggers

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

| Line | What It Does |
|------|-------------|
| `name:` | Human-readable label — shows up in the GitHub Actions UI. Call it anything you like |
| `on:` | "When should this pipeline run?" |
| `push: branches: [main]` | Run when someone pushes to main (or a PR gets merged, which is a push) |
| `pull_request: branches: [main]` | Run when someone opens or updates a PR targeting main |

**Why both triggers?** On a PR, you want to run lint and test to catch problems before the code gets merged. But you don't want to deploy on a PR — that only happens when code lands on main. We'll handle that distinction later with a conditional on the deploy job.

### 4b — Environment Variables

```yaml
env:
  IMAGE_NAME: api-service
  APP_PORT: 3000
```

`env:` is a top-level key (same level as `name:` and `on:`). It defines variables available to every job in the pipeline. The reason we do this is so you're not hardcoding `api-service` and `3000` in ten different places. If the port ever changes, you change it once here.

### 4c — The Lint Job

```yaml
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
```

| Line | What It Does |
|------|-------------|
| `jobs:` | Top-level key. Everything below defines the actual work |
| `lint:` | Job ID — an internal name you choose. Other jobs reference this when they depend on it |
| `name: Lint` | Human-readable name that shows in the GitHub Actions UI |
| `runs-on: ubuntu-latest` | Every job runs on a fresh virtual machine. This says "give me a clean Ubuntu box" |
| `steps:` | The ordered list of things this job does. They run top to bottom. If any step fails, the job stops |

**Understanding the steps:**

**Checkout code** — the fresh VM starts completely empty. It doesn't have your code. `actions/checkout@v4` is a pre-built action that clones your repo onto the VM. It knows which repo to clone because the pipeline was triggered by a push to that repo — the context is automatic.

**Setup Node.js** — the VM doesn't have Node installed at the right version. This action installs Node 18 specifically.

**Install dependencies** — `npm ci` reads `package.json` from the `./app` directory and installs the packages listed in it. It only reads `package.json` (and `package-lock.json`) — it doesn't scan every file. After this step, the linter (ESLint) exists in `node_modules/` and can be run.

`npm ci` vs `npm install`: `npm ci` reads the lockfile and installs exactly what's in there — no recalculating, no updating. In a pipeline you want deterministic builds. `npm install` might update versions, which means your pipeline could pass with different package versions than what was tested locally.

`working-directory: ./app` tells the step to run from inside the `app/` folder, because that's where `package.json` lives.

**Run linter** — `npm run lint` reads the `scripts` section of `package.json`, finds `"lint": "eslint server.js"`, and runs that command. ESLint loads rules from `.eslintrc.json` and checks `server.js` against them. If it finds problems, this step fails and the pipeline stops here.

### Understanding Fresh VMs and Runners

When your pipeline triggers, GitHub spins up a fresh virtual machine from their own pool of servers. These are machines GitHub owns — not your AWS account. Your job gets assigned one, it runs, and when the job finishes the VM is destroyed.

**Why fresh every time?** Consistency. If a previous run left behind files or changed config, that could affect the next run. Starting clean means your pipeline either works because it's correct, or fails because it's broken — never passes by accident.

**What about on-prem?** That's where self-hosted runners come in. You install a small agent on your own machine and register it with GitHub. Then you write `runs-on: self-hosted` instead of `runs-on: ubuntu-latest`. Big companies do this to access internal systems or control hardware for security reasons.

Other CI/CD tools handle it differently too — Jenkins runs everything on servers you manage yourself. There's no "GitHub gives you a free VM."

### 4d — The Test Job

```yaml
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
```

`needs: lint` is the key new concept. It means "don't start this job until the lint job has passed." If lint fails, this job never runs. This creates the dependency chain: lint → test.

**Why do we checkout and install dependencies again?** Each job gets a fresh VM. The lint job's VM is gone. This is a brand new machine that starts with nothing.

**Why not put lint and test in the same job?** You could. But separating them gives clearer visibility in the GitHub UI — you can see at a glance "lint passed, test failed" rather than digging through one big log.

### 4e — The Build Job

```yaml
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
```

The chain is now lint → test → build.

Breaking down the `docker build` command:

| Component | What It Does |
|-----------|-------------|
| `docker build` | Build a Docker image from a Dockerfile |
| `-t` | Tag the image (give it a name and version) |
| `${{ env.IMAGE_NAME }}` | Pulls the `IMAGE_NAME` variable from the `env:` block — resolves to `api-service` |
| `${{ github.sha }}` | The git commit SHA — a unique hash like `a1b2c3d4`. GitHub Actions provides this automatically |
| `./app` | Build from the `app/` directory, where the Dockerfile lives |

The full tag becomes something like `api-service:a1b2c3d4e5f6`.

**Why tag with the commit SHA instead of `latest`?** Traceability. If something breaks in production, you look at the running container's tag and immediately know which commit is deployed. With `latest` you'd have to dig through logs to figure out which version is running.

Notice we don't need Node.js setup or `npm ci` here. Docker handles all of that inside the image build using the Dockerfile's own instructions.

### 4f — The Deploy Job

```yaml
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
```

`needs: build` — chain is now lint → test → build → deploy.

The `if:` line is the conditional:

| Condition | What It Checks |
|-----------|---------------|
| `github.event_name == 'push'` | Was this triggered by a push, not a pull request? |
| `github.ref == 'refs/heads/main'` | Was the push to the main branch? |

Both must be true. If someone opens a PR, the pipeline runs lint, test, and build — but stops. Deploy only happens when code lands on main. `refs/heads/main` is how Git refers to branches internally — `refs/heads/` is the prefix for all branches.

The deploy step:

| Component | What It Does |
|-----------|-------------|
| `run: \|` | The pipe means "multi-line script" — lets you write multiple commands |
| `chmod +x deploy.sh` | Makes the deploy script executable |
| `./deploy.sh ${{ github.sha }}` | Runs the deploy script, passing the commit SHA as an argument |

### 4g — The Smoke Test Job

```yaml
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

The chain is complete: lint → test → build → deploy → smoke-test.

Same `if:` conditional as deploy — only runs on pushes to main.

The first step waits 5 seconds — containers need a moment to start up.

Breaking down the health check `curl` command:

| Component | What It Does |
|-----------|-------------|
| `for i in 1 2 3 4 5` | Try up to 5 times |
| `curl` | Make an HTTP request |
| `-s` | Silent mode — don't show progress bars |
| `-f` | Treat HTTP errors (like 500) as failures |
| `-o /dev/null` | Throw away the response body — we only care about the status code |
| `-w "%{http_code}"` | Print just the HTTP status code (200, 404, 500 etc.) |
| `http://localhost:${{ env.APP_PORT }}/health` | Hit the health endpoint using our port variable |
| `\|\| true` | If curl fails completely (connection refused), don't kill the script — we handle it ourselves |
| `sleep 3` | Wait 3 seconds between retries |
| `exit 0` | Health check passed — end the script with success |
| `exit 1` | All 5 attempts failed — end the script with failure |

---

## Step 5 — Create the Deploy Script

Create `deploy.sh` in the lab root (not inside `app/`):

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

**The safety line:**

| Flag | What It Does |
|------|-------------|
| `set -e` | Exit immediately if any command fails |
| `set -u` | Error if you try to use a variable that hasn't been set |
| `set -o pipefail` | If any command in a pipeline fails, the whole pipe fails |

**The tag parameter:**

`TAG="${1:?Usage: deploy.sh <image-tag>}"` takes the first argument passed to the script. When the pipeline runs `./deploy.sh a1b2c3d4`, `$1` equals `a1b2c3d4` and `TAG` gets set to that value.

The `${1:?...}` syntax is a bash pattern meaning "if this variable is empty or unset, print this error and exit." It's a guard rail — if someone runs `./deploy.sh` with no argument, it refuses to continue rather than deploying with an empty tag.

Related bash patterns worth knowing:

| Pattern | Meaning |
|---------|---------|
| `${VAR:?error}` | Required — if empty/unset, print error and exit |
| `${VAR:-default}` | Optional — if empty/unset, use this default instead |
| `${VAR:+alternative}` | If VAR is set, use this alternative value |

**Stop and remove existing container:**

| Component | What It Does |
|-----------|-------------|
| `docker stop "$CONTAINER_NAME"` | Stop the running container |
| `docker rm "$CONTAINER_NAME"` | Remove it so the name is free for the new one |
| `2>/dev/null` | Redirect error messages to nowhere — if there's no container, Docker complains "no such container" and we don't care |
| `\|\| true` | If the command fails (nothing to stop), don't let `set -e` kill the script |

**Start the new container:**

| Component | What It Does |
|-----------|-------------|
| `docker run` | Start a new container |
| `-d` | Detached mode — runs in the background. Without this the script would hang |
| `--name "$CONTAINER_NAME"` | Give the container a name so we can reference it later |
| `-p "${PORT}:${PORT}"` | Map host port to container port. `3000:3000` means traffic on host port 3000 goes to container port 3000 |
| `"${IMAGE_NAME}:${TAG}"` | Which image to run — resolves to something like `api-service:a1b2c3d4` |
| `\` | Line continuation — splits one long command across multiple lines for readability |

**The health check and rollback:**

The retry loop tries 5 times to get a 200 from the health endpoint. If it succeeds, `exit 0` terminates the entire script immediately — the rollback section below the loop never executes. If all 5 attempts fail, the loop finishes naturally and execution falls through to the rollback, which stops and removes the broken container so it's not left running.

`exit 0` means success (pipeline marks the job as passed). `exit 1` means failure (pipeline marks the job as failed).

---

## Step 6 — Validate

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

The pipeline you've built covers the fundamentals. Here's what a production pipeline would add — these are the things to mention when an interviewer asks "what does your golden pipeline look like?"

### Quality Gates You'd Add

**SAST scan** (e.g. Snyk, Trivy) — scans code and dependencies for known vulnerabilities. Goes after test, before build.

**Container image scan** — scans the built Docker image for CVEs. Goes after build, before deploy.

**Code coverage threshold** — fails the pipeline if test coverage drops below a minimum (e.g. 80%). Goes in the test stage.

**Manual approval gate** — requires a human to click "approve" before production deploy. Goes between build and deploy.

### Environment Promotion

In a real setup, you wouldn't deploy straight to production. The pattern is:

```
PR → Lint + Test
Merge to main → Build → Deploy to staging → Integration tests → Manual approval → Deploy to production
```

Each environment has its own deploy step with its own health checks.

### Feature Flags

Feature flags let you deploy code that contains a new feature but keep the feature switched off until you're ready. This decouples deployment (shipping code) from release (enabling features for users). Tools like LaunchDarkly or even a simple environment variable:

```javascript
if (process.env.FEATURE_NEW_DASHBOARD === 'true') {
  // show new dashboard
} else {
  // show old dashboard
}
```

You can deploy every day but release features on your own schedule. If a feature causes problems, you toggle the flag off — no rollback, no redeploy.

### Notifications

Production pipelines send notifications on failure — Slack messages, PagerDuty alerts, email. The team should know immediately if a deploy fails, not find out when customers complain.

---

## Interview Talking Points

**"Walk me through your CI/CD pipeline":**

1. "Code gets pushed to a PR. The pipeline runs lint and tests automatically — if either fails, the PR can't merge."
2. "Once merged to main, the pipeline builds a Docker image tagged with the commit SHA — never `latest`, because we need traceability."
3. "The deploy stage pulls the new image, stops the old container, and starts the new one."
4. "After deploy, a smoke test hits the health endpoint. If it fails after five retries, the pipeline fails and we know immediately."
5. "For production, I'd add a SAST scan, image scanning, environment promotion through staging, and a manual approval gate."

**"Have you ever optimised a pipeline?":**

- "I separated lint and test into independent jobs so they could theoretically run in parallel, reducing total pipeline time."
- "I used `npm ci` instead of `npm install` because it's faster and deterministic — it installs exactly what's in the lockfile."
- "I tagged images with the git SHA instead of `latest` so we always know exactly which commit is deployed."

**"What's the difference between deployment and release?":**

- "Deployment is shipping code to a server. Release is enabling a feature for users. With feature flags you can deploy daily but release on your own schedule."

---

## Lab vs Real Life

| This Lab | Real Production |
|----------|----------------|
| Single environment (local) | Multiple environments — staging, production, sometimes QA |
| No secrets management | Secrets stored in GitHub Secrets, Vault, or AWS SSM — never in code |
| No image registry | Images pushed to ECR, Docker Hub, or GitHub Container Registry |
| Deploy script runs locally | Deploy targets a remote server or Kubernetes cluster |
| No approval gates | Manual approval required before production deploy |
| No notifications | Slack/PagerDuty alerts on failure |
| No rollback strategy beyond stopping | Blue-green or canary deployments for zero-downtime rollback |

---

## Cleanup and Reset

To reset this lab and start fresh:

```bash
rm -rf .github/
rm -f deploy.sh
```

This removes everything you created, leaving just the app files and lab infrastructure. You can re-run the lab from Step 1.
