# Lab 042 — Pipeline Secrets Injection

## TLDR — Plain English Summary

Imagine you bake your house key into a birthday cake and then post a photo of that cake on the internet. Even if you later bake a new cake without the key, the original photo is still out there — and anyone can look at it. That's exactly what this lab is about.

The broken setup bakes AWS credentials (your access keys) directly into a Docker image during the build process. Docker images are made of layers, and every layer is permanently recorded in the image's history. Anyone who can pull the image — or even just run `docker history` — can read those credentials in plain text. The fix is simple in concept: **never put secrets in the image**. Build the image with just the application code. Pass the credentials in at runtime, only to the processes that actually need them, only when they're running.

There are three specific bugs to find and fix:

1. The `Dockerfile` uses `ARG` and `ENV` to pull secrets into the image at build time.
2. The GitHub Actions workflow passes those secrets to the Docker build using `--build-arg`, which bakes them into image layer metadata.
3. The workflow references the wrong secret names (`ACCESS_KEY`, `SECRET_KEY`) instead of the standard AWS names — so even if the rest were correct, the credentials would be empty strings.

---

## Step 0 — Start the Lab and Orient Yourself

Before touching anything, get into the lab directory and read what's there.

```bash
# Start the lab
lab start 042

# Navigate into the lab directory
cd ~/cloud-engineer-labs/cicd-labs/lab-042-pipeline-secrets-injection

# See what files are present
ls -la
```

You should see:
- `CHALLENGE.md` — the scenario and objectives
- `Dockerfile` — the broken Docker image definition
- `.github/workflows/deploy.yml` — the broken GitHub Actions workflow
- `validate.sh` — run this when you're ready to check your fixes

**Read `CHALLENGE.md` first.** It gives you the incident description and objectives without spoiling the bugs. Then open the two broken files and read them top to bottom before changing anything.

```bash
cat CHALLENGE.md
cat Dockerfile
cat .github/workflows/deploy.yml
```

This is a file-based lab — there are no containers to start and nothing to `docker-compose up`. The broken state is already present in the files. Your job is to find and fix it.

---

## Diagnostic Pathway — How to Think Through This

When a deployment pipeline fails with credential errors, or when you're asked to audit a pipeline for secret handling, here is the logical sequence an engineer follows.

---

### Stage 1 — Start with the error symptom

**What are you seeing?**

The pipeline runs but AWS commands fail. The typical error is something like:

```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

or

```
An error occurred (AuthFailure) when calling the... operation: AWS was not able to validate the provided access credentials
```

**Why does this happen?**

Either the credentials were never made available to the process, or the names used to reference them are wrong — resulting in empty environment variables.

**First question to ask yourself:** Are credentials even being passed to the step that needs them?

---

### Stage 2 — Read both files top to bottom before changing anything

Open the `Dockerfile` and the workflow file and read them completely first. Don't start fixing on instinct.

```bash
cat Dockerfile
cat .github/workflows/deploy.yml
```

In the `Dockerfile` you will see `ARG` and `ENV` instructions referencing credentials:

```dockerfile
ARG AWS_ACCESS_KEY_ID
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
```

Your first instinct might be that this is fine because there are no hardcoded values — it's just referencing a variable, not pasting in a real key. **This is a common misconception.** The credentials are not hardcoded here, but the mechanism to receive and permanently store them is. The question to ask is: where does the real value come from, and what happens to it?

---

### Stage 3 — Trace the full chain from secret to image

Follow the value through the system step by step:

1. GitHub stores the real credential under a secret name (e.g. `ACCESS_KEY`)
2. The workflow passes it into the Docker build: `--build-arg AWS_ACCESS_KEY_ID=${{ secrets.ACCESS_KEY }}`
3. The `${{ secrets.ACCESS_KEY }}` reference is resolved to the **real credential value** before Docker even starts
4. Docker receives the real value and the `ARG` instruction captures it
5. The `ENV` instruction then writes that real value **permanently into the image layer**

The key insight: by the time Docker sees it, the reference has already been substituted for the real thing. The image layer now contains the actual credential, not a reference to it.

**Why does this matter?** Docker images are made of layers and every layer is permanent. Run this against any image built this way:

```bash
docker history myapp:latest
```

The credential values will be visible in the output. Anyone with read access to the image registry can extract them.

---

### Stage 4 — Understand what the Dockerfile actually needs to do

The Dockerfile's only job is to package the application so it can run anywhere. It does not need credentials to do that.

Credentials are needed by two things — neither of which is the image itself:

- **The workflow** — to authenticate with AWS when pushing the image to ECR
- **The running container** — when it starts up on a server and needs to connect to AWS or a database

Both of those happen outside the image build. The workflow already has credentials available via GitHub secrets. The running container receives them at startup from the platform (ECS task definition, Kubernetes secrets, `docker run -e`) — not from the image.

**A useful distinction:** Not all environment variables in a Dockerfile are wrong. The rule is specific:

| Type | Example | OK in Dockerfile? |
|---|---|---|
| Non-sensitive config | `ENV NODE_ENV=production` | Yes — knowing this reveals nothing sensitive |
| Credentials or secrets | `ENV AWS_ACCESS_KEY_ID=...` | Never — baked permanently into the image |

---

### Stage 5 — Audit everything before fixing

Don't just fix the one thing that caused the visible error. Check the full scope first.

```bash
# Find all ARG and ENV lines in the Dockerfile
grep -iE "ARG|ENV" Dockerfile

# Find all secret references and build-arg usage in the workflow
grep -i "build-arg\|secrets\." .github/workflows/deploy.yml
```

In this lab you will find three credentials affected in the Dockerfile (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DATABASE_URL`) and two bugs in the workflow (wrong secret names and `--build-arg` passing).

---

### Stage 6 — Apply the fixes

Now that you understand what the problem is and why it exists, the fixes are straightforward. Work through them one at a time.

---

## File-by-File Breakdown

Before fixing anything, read both files completely and understand what every line is doing. This section explains each line in plain English — including which lines are bugs and why.

---

### The deploy.yml — Line by Line

```yaml
name: Deploy
```
Just a label. This is the name that appears in the GitHub Actions UI so you can identify this workflow. Has no effect on what it does.

---

```yaml
on:
  push:
    branches: [main]
```
**When does this workflow run?** Only when someone pushes code to the `main` branch. This is the trigger. Nothing in this file runs unless that condition is met.

---

```yaml
jobs:
  deploy:
```
A workflow is made up of jobs. This one has a single job called `deploy`. If you had multiple jobs they would be listed here side by side.

---

```yaml
    runs-on: ubuntu-latest
```
Which computer should this job run on? GitHub spins up a fresh Ubuntu Linux virtual machine for every run. Your code doesn't run on your Pi — it runs on GitHub's servers.

---

```yaml
    steps:
```
A job is made up of steps — individual tasks that run in order, one after another.

---

```yaml
    - uses: actions/checkout@v4
```
Step 1. `uses` means "run this pre-built Action". `actions/checkout` is an official GitHub Action that downloads your repository code onto the virtual machine. Without this, the VM has no idea what your code looks like.

---

```yaml
    - name: Configure AWS
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.ACCESS_KEY }}
        aws-secret-access-key: ${{ secrets.SECRET_KEY }}
        aws-region: eu-west-2
```
Step 2. A pre-built Action that sets up the AWS CLI with credentials so subsequent steps can talk to AWS. `with:` passes inputs into the Action — think of them as settings.

`${{ secrets.ACCESS_KEY }}` reads a secret stored in GitHub Settings by name.

**BUG 3 — Wrong secret names.** The secrets are stored in GitHub as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` — but this step is looking for `ACCESS_KEY` and `SECRET_KEY`. Those don't exist. GitHub returns empty strings with no error or warning. AWS gets no credentials and everything fails silently.

There is no way to know from the workflow file alone what names the secrets are stored under — you have to go to GitHub → Repository → Settings → Secrets and Variables → Actions and check. The standard AWS convention (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) is well established — seeing `ACCESS_KEY` and `SECRET_KEY` is immediately suspicious to an experienced engineer.

**Fix:**
```yaml
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

---

```yaml
    - name: Login to ECR
      uses: aws-actions/amazon-ecr-login@v2
```
Step 3. Logs into Amazon's container registry (ECR) — the place where Docker images are stored. You need to be authenticated before you can push an image there. This step uses the AWS credentials configured in Step 2.

Nothing wrong with this line.

---

```yaml
    - name: Build and push
      run: |
        docker build \
          --build-arg AWS_ACCESS_KEY_ID=${{ secrets.ACCESS_KEY }} \
          --build-arg AWS_SECRET_ACCESS_KEY=${{ secrets.SECRET_KEY }} \
          --build-arg DATABASE_URL=${{ secrets.DATABASE_URL }} \
          -t $ECR_REGISTRY/app:${{ github.sha }} .
        docker push $ECR_REGISTRY/app:${{ github.sha }}
```
Step 4. `run:` means run a shell command directly — not a pre-built Action.

`docker build` — builds the image from the Dockerfile.

**BUG 2 — Secrets passed as `--build-arg`.** Each `--build-arg` flag passes a secret value into the Docker build. By the time Docker sees it, the `${{ secrets.ACCESS_KEY }}` reference has already been resolved to the real credential value. The Dockerfile receives it via `ARG` and bakes it permanently into the image layer via `ENV`. Also uses the wrong secret names again.

`-t $ECR_REGISTRY/app:${{ github.sha }}` — tags the image. `$ECR_REGISTRY` is the address of your ECR registry. `${{ github.sha }}` is the Git commit hash — used as a unique version tag so every build is distinctly labelled.

`.` — the build context. Tells Docker to use the current directory, which contains your Dockerfile.

`docker push` — pushes the finished image up to ECR. Nothing wrong with this line.

**Fix — remove all three `--build-arg` lines:**
```yaml
      run: |
        docker build -t $ECR_REGISTRY/app:${{ github.sha }} .
        docker push $ECR_REGISTRY/app:${{ github.sha }}
```

---

### The Dockerfile — Line by Line

```dockerfile
FROM node:20-alpine
```
The starting point. Every Dockerfile begins with `FROM` — it defines the base image. `node:20-alpine` means: start with a minimal Linux operating system (Alpine) that already has Node.js version 20 installed. Alpine is used because it's tiny — keeps the image small.

Nothing wrong with this line.

---

```dockerfile
WORKDIR /app
```
Sets the working directory inside the container. Every instruction that follows runs from this location. It's the equivalent of `cd /app` — except it also creates the folder if it doesn't exist.

Nothing wrong with this line.

---

```dockerfile
COPY package.json .
```
Copies `package.json` from your project into `/app` inside the container. The `.` means "copy it here, into the current working directory." `package.json` is a Node.js file that lists all the dependencies your application needs — like a shopping list.

Nothing wrong with this line.

---

```dockerfile
RUN npm install
```
Runs a command at build time. Reads `package.json` and installs all the dependencies listed in it. This creates a layer in the image containing all those installed packages.

This is why `package.json` was copied in the step before — `npm install` needs it to know what to install. It also comes before `COPY . .` deliberately — so that if you only change your app code but not your dependencies, Docker can reuse the cached `npm install` layer and skip reinstalling everything.

Nothing wrong with this line.

---

```dockerfile
COPY . .
```
Copies everything else from your project directory into `/app` inside the container. This is where your actual application code lands — `server.js` and any other files.

Nothing wrong with this line.

---

```dockerfile
ARG DATABASE_URL
ENV DATABASE_URL=$DATABASE_URL
```
**BUG 1 — first credential.**

`ARG DATABASE_URL` declares that the Docker build is willing to receive a value called `DATABASE_URL` from whoever is running `docker build`. That value comes from the `--build-arg DATABASE_URL=...` flag in the `deploy.yml`.

`ENV DATABASE_URL=$DATABASE_URL` takes that received value and writes it permanently into the image as an environment variable in this layer.

The database URL is sensitive — it typically contains the address, username, and password for your database. Baking it into the image means anyone who can pull the image can read it via `docker history`.

**Fix: remove both lines.**

---

```dockerfile
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
```
**BUG 1 continued — the other two credentials.**

Same pattern. `ARG` receives the values from `--build-arg` in the workflow. `ENV` bakes them permanently into the image layer. These are your AWS credentials — the most sensitive values in the entire setup. Anyone with the image can run `docker history` and read them in plain text.

It may look safe because there are no hardcoded values — just variable references. But the reference is resolved to the real credential value before Docker even starts. By the time `ENV` runs, it is writing the actual key, not a reference.

**Fix: remove all four lines.**

---

```dockerfile
CMD ["node", "server.js"]
```
Defines what command runs when the container starts. This is not a build-time instruction — nothing happens here during `docker build`. It is a declaration that says "when someone runs this image, start the app by running `node server.js`."

Nothing wrong with this line.

---

## Step-by-Step Fix

### Step 1 — Remove all credential lines from the Dockerfile

Open `Dockerfile`. Find and remove the `ARG`/`ENV` blocks for credentials. Also remove the `ARG` lines — if nothing is writing the value into an `ENV`, the `ARG` declarations serve no purpose either.

**Broken version:**
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .

ARG DATABASE_URL
ENV DATABASE_URL=$DATABASE_URL

ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

CMD ["node", "server.js"]
```

**Fixed version:**
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "server.js"]
```

**What each instruction does:**

| Instruction | What it does |
|---|---|
| `FROM node:20-alpine` | Sets the base image — a minimal Linux image with Node.js 20 pre-installed |
| `WORKDIR /app` | Sets the working directory inside the container for all subsequent instructions |
| `COPY package.json .` | Copies `package.json` into `/app` |
| `RUN npm install` | Installs Node dependencies — runs at build time and creates an image layer |
| `COPY . .` | Copies the rest of the application code into `/app` |
| `CMD ["node", "server.js"]` | Defines the default command to run when the container starts |

**Why the removed lines were dangerous:**

| Instruction | What it was doing |
|---|---|
| `ARG AWS_ACCESS_KEY_ID` | Declares a build argument — Docker build receives this value from the command line at build time |
| `ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID` | Takes that build arg value and writes it permanently into the image as an environment variable in this layer |

Once an `ENV` is written to an image layer, it is there forever — even if a later layer overwrites it, the original value is still readable in the layer history.

---

### Step 2 — Remove `--build-arg` flags from the workflow

Open `.github/workflows/deploy.yml` and find the Build and push step.

**Broken version:**
```yaml
- name: Build and push
  run: |
    docker build \
      --build-arg AWS_ACCESS_KEY_ID=${{ secrets.ACCESS_KEY }} \
      --build-arg AWS_SECRET_ACCESS_KEY=${{ secrets.SECRET_KEY }} \
      --build-arg DATABASE_URL=${{ secrets.DATABASE_URL }} \
      -t $ECR_REGISTRY/app:${{ github.sha }} .
    docker push $ECR_REGISTRY/app:${{ github.sha }}
```

**Fixed version:**
```yaml
- name: Build and push
  run: |
    docker build -t $ECR_REGISTRY/app:${{ github.sha }} .
    docker push $ECR_REGISTRY/app:${{ github.sha }}
```

**What each part does:**

| Flag / Component | What it does |
|---|---|
| `docker build` | The Docker CLI command to build an image from a Dockerfile |
| `--build-arg KEY=VALUE` | Passes a variable into the Docker build process, accessible via `ARG` in the Dockerfile. Stored in image metadata — visible via `docker history` |
| `-t $ECR_REGISTRY/app:${{ github.sha }}` | Tags the image. `-t` is short for `--tag`. `github.sha` is the Git commit hash — used as a unique version tag |
| `.` | The build context — the directory Docker packages up and sends to the daemon |
| `docker push` | Pushes the tagged image to the ECR repository |

---

### Step 3 — Fix the secret names in the workflow

Find the Configure AWS step in the workflow.

**Broken version:**
```yaml
- name: Configure AWS
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.ACCESS_KEY }}
    aws-secret-access-key: ${{ secrets.SECRET_KEY }}
    aws-region: eu-west-2
```

**Fixed version:**
```yaml
- name: Configure AWS
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: eu-west-2
```

**What's happening here:**

| Part | What it does |
|---|---|
| `uses: aws-actions/configure-aws-credentials@v4` | A pre-built GitHub Action that handles AWS authentication — you give it credentials, it configures the AWS CLI for all subsequent steps in the job |
| `aws-access-key-id: ...` | The input parameter this Action expects — maps to the `AWS_ACCESS_KEY_ID` environment variable internally |
| `${{ secrets.AWS_ACCESS_KEY_ID }}` | Reads the GitHub secret whose name is `AWS_ACCESS_KEY_ID`. If the name doesn't match exactly, GitHub returns an empty string — no error, no warning |

**Why wrong names cause silent failures:** GitHub does not raise an error for a missing secret reference. `${{ secrets.NONEXISTENT }}` evaluates to an empty string. The AWS CLI then receives an empty credential and reports "Unable to locate credentials" — the error looks like a configuration problem, not a typo. This is one of the most common causes of confusing pipeline failures.

---

### Step 4 — Validate your fixes

```bash
lab validate 042
```

All four checks should pass:
- Dockerfile doesn't contain AWS credentials
- No secret access key in Dockerfile
- No secrets passed as Docker build args
- Workflow uses standard AWS credential names

---

### Step 5 — Manual verification

After validation, confirm both files look clean:

```bash
# Confirm no credential references remain in the Dockerfile
grep -iE "AWS_ACCESS_KEY|AWS_SECRET|DATABASE_URL" Dockerfile

# Confirm no --build-arg secret passing remains in the workflow
grep -iE "build-arg" .github/workflows/deploy.yml
```

**What these commands do:**

| Part | What it does |
|---|---|
| `grep` | Searches for a pattern in a file |
| `-i` | Case-insensitive — matches regardless of capitalisation |
| `-E` | Extended regular expressions — enables the pipe character as OR |
| `"AWS_ACCESS_KEY\|AWS_SECRET\|DATABASE_URL"` | The pattern to search for — any of these three strings |

Both commands should return **nothing**. Any output means there is still a reference to clean up.

---

## Environment Notes

- **This lab uses GitHub Actions** — the workflow file lives at `.github/workflows/deploy.yml` in the repo
- **AWS credentials** should be stored in GitHub Settings → Secrets and Variables → Actions with the exact names `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- **In real AWS environments**, you would use IAM roles for ECS/EC2 instead of long-lived access keys — the application never needs to see credentials at all. This lab teaches the correct handling of access keys for the cases where they are unavoidable

---

## Real-World Context

| Practice | What it means in production |
|---|---|
| IAM roles instead of access keys | ECS tasks and EC2 instances can be assigned an IAM role. AWS SDKs automatically use it — no credentials in environment variables at all |
| AWS Secrets Manager | Database URLs and API keys are stored in Secrets Manager and injected into ECS task definitions via `valueFrom` at container startup |
| OIDC for GitHub Actions | GitHub can directly assume an IAM role via federation — no long-lived access keys stored in GitHub Secrets at all |
| Docker BuildKit secrets | If you genuinely need a secret at build time (e.g. a private npm registry token), use `--mount=type=secret` which is never written to image layers |
| Image scanning | Trivy or Snyk scans images for leaked secrets and vulnerabilities before they are pushed to the registry |

---

## Cleanup / Reset

To reset the lab back to the broken state so you can run through it again from Step 0, use `git checkout` to restore both files to their committed broken state:

```bash
git checkout -- Dockerfile
git checkout -- .github/workflows/deploy.yml
```

That's it. No manual editing — git throws away your local changes and restores both files exactly as they are in the repo.

Confirm you're back to the broken state:

```bash
grep -iE "ARG|ENV" Dockerfile
grep -i "build-arg" .github/workflows/deploy.yml
```

Both commands should return output confirming the broken lines are present before re-attempting.
