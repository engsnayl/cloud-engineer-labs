# Lab 043 — Bad Deploy / Rollback Strategy: Solution Walkthrough

## TLDR (Plain English)

A bad version of an app went live yesterday. The team had no automated way to put the old version back, so an engineer had to manually figure out what was running before and redeploy it by hand — which took 45 minutes of downtime.

Our job is to make the deploy script smarter so this never happens again. We need it to do three things it currently doesn't do:

1. **Remember what was running before it deploys** — so we have something to fall back to.
2. **Check the new version actually works after deploying** — by hitting a health URL a few times.
3. **Automatically put the old version back if the new one is broken** — instead of waiting for a human.

We'll also make the script take a version number as an argument (e.g. `./deploy.sh v1.2.3`) instead of always blindly deploying whatever is tagged `latest`. That way we always know exactly what we're shipping.

---

## The Ticket

> **INCIDENT-CICD-003**: Bad code deployed to production. No rollback mechanism. Manual revert took 45 minutes. Need to implement rollback strategy.

You've been handed this incident. Nobody has briefed you on what's specifically wrong — just that yesterday's deploy was bad and recovery was painful. Your job is to investigate the deploy process, work out why recovery was slow, and fix it so the next bad deploy is recovered automatically.

---

## Step 1 — Understand the lay of the land

You arrive at the lab directory. First instinct: see what's here.

```bash
ls -la
```

You see `deploy.sh`, `setup.sh`, `validate.sh`, and a `CHALLENGE.md`. The `setup.sh` exists to put the environment into a realistic "production has something running already" state — run it once before you start.

```bash
./setup.sh
```

Now check what's running, exactly as you would on a real server:

```bash
docker ps
```

You see one container called `app` running `myapp:latest`. That's "production" for this lab.

**Reasoning at this point:** I have a deploy script and a running app. The ticket says recovery was manual and took 45 minutes. Before I touch anything, I need to read the deploy script and figure out *why* recovery was manual. The script itself is the thing that failed the team — not the bad code that was deployed. The bad code is going to happen again at some point; what we control is whether the system handles it.

---

## Step 2 — Read the existing deploy script

```bash
cat deploy.sh
```

```bash
#!/bin/bash
# Production deployment script

echo "Deploying version: latest"

docker stop app 2>/dev/null
docker rm app 2>/dev/null
docker pull myapp:latest
docker run -d --name app -p 8080:8080 myapp:latest

echo "Deployed!"
```

Six lines of actual logic. Read each one and ask: *what would happen if this step's outcome were bad?*

| Line | What it does | What if it goes wrong? |
|---|---|---|
| `docker stop app` | Stops the running container | Fine — the existing version stops cleanly |
| `docker rm app` | Removes the stopped container | At this point the old version is **gone** — no record of what was running |
| `docker pull myapp:latest` | Pulls the new image | We've already destroyed the old container before knowing if the new one works |
| `docker run -d ... myapp:latest` | Starts the new version | Script ends here. If the new container crash-loops or returns 500 errors, **this script doesn't know and doesn't care** |
| `echo "Deployed!"` | Prints success | Prints "Deployed!" even if the app is on fire |

So now you've discovered the problems yourself, just by reading carefully:

1. **No way to roll back.** By the time `docker run` happens, the old container is already deleted. If we wanted to put it back, we'd have to know what version it was — and the script never wrote that down anywhere.
2. **No verification.** The script declares success the moment `docker run` returns. But `docker run` only fails if Docker itself fails — it returns success even if your app immediately crashes inside the container.
3. **`latest` is meaningless.** Every deploy uses the tag `latest`. There is no way to ask "what version is running?" and get a useful answer. There is no way to say "deploy v1.2.2" or "roll back to v1.2.1" because those are just abstract ideas — the script only knows about `latest`.

That's the root cause of the 45-minute manual recovery from yesterday. The on-call engineer had to:

- Work out what version was running before (probably from Slack/git logs)
- Manually pull that image
- Manually start it

We can automate every single step of that.

---

## Step 3 — Decide what the new script needs to do

Before writing any code, sketch the flow you want:

1. Take a version as an argument so we know exactly what we're deploying.
2. **Before stopping the old container**, record what image it's running. This is our rollback target.
3. Stop and remove the old container (only after we've recorded its version).
4. Start the new container.
5. Hit the app's health endpoint repeatedly — apps take a few seconds to start, so retry a handful of times before giving up.
6. **If the health check passes**, we're done.
7. **If the health check fails**, redeploy the version we recorded in step 2.

Notice that step 2 has to happen before step 3, and step 5 has to happen before step 6 or 7. The order is the whole point.

**Pause and ask: do I have what I need?** 

- A health endpoint to hit? Yes — `setup.sh` builds a Flask app with `/health` on port 8080. In a real situation, you'd ask the dev team or read the app's docs.
- A way to read the currently-running container's image tag? `docker inspect` — we'll come back to the exact incantation.
- A way to take command-line arguments in bash? Yes — `$1` is the first argument.

---

## Step 4 — Build it piece by piece

We'll build the new `deploy.sh` in the order the script will execute, testing the thinking as we go.

> **⚠ Important — these are file contents, not commands to type at the prompt.**
>
> The code blocks in this section are pieces of the new `deploy.sh` we're going to write. You **do not** type them into your SSH terminal one line at a time. We're going to assemble them in your head (or on paper) and then write the whole thing into `deploy.sh` in one go at Step 5.
>
> This matters because two of the lines we're about to write will actively kill your interactive shell if you paste them at the prompt:
> - `set -e` tells bash "exit immediately on any error" — applied to your live SSH shell, this means your session terminates the moment anything fails.
> - `${1:?Usage: ...}` tells bash "fail if the first argument is empty" — at an interactive prompt where there is no `$1`, this fails immediately.
>
> Combine the two and pasting them straight into your SSH session will eject you. That behaviour is correct: those safeguards are exactly what we *want* inside a script. They're just not safe to run interactively.
>
> So: read Steps 4a through 4e to understand each piece, then go to Step 5 to actually write the file.

### 4a. Take a version argument and define some constants

```bash
#!/bin/bash
set -e

VERSION=${1:?Usage: ./deploy.sh <version>}
IMAGE_NAME="myapp"
CONTAINER_NAME="app"
HEALTH_URL="http://localhost:8080/health"
MAX_RETRIES=10
RETRY_INTERVAL=3
```

**Why two separate variables?** This trips people up the first time. The image and the container are two different things:

- **Image**: `myapp:v1.0.0` — the read-only blueprint. The thing you `docker pull` or `docker build`.
- **Container**: a running instance of an image. You can run multiple containers from the same image, and you give each one a name with `--name`. Look at the existing `setup.sh` (or the original broken `deploy.sh`) and you'll see `--name app` — so the running container is called `app`, **not** `myapp`.

If we used a single `APP_NAME="myapp"` variable for both, then `docker inspect myapp` (in the next step) would fail to find the container — there is no container called `myapp`, only an image. That would silently break our rollback. Keeping them separate is also closer to real life: one host might run several containers from the same image (e.g. `nginx` image as containers `nginx-frontend` and `nginx-admin`).

**Command breakdown:**

| Component | What it means |
|---|---|
| `set -e` | If any command in this script fails, stop the script immediately. Without this, errors get silently swallowed. |
| `${1:?Usage: ...}` | "Take the first command-line argument. If it's missing or empty, exit with this error message." The `?` is what makes it required. |
| `IMAGE_NAME="myapp"` | The Docker image name. Combined with `$VERSION` to give the full tag, e.g. `myapp:v1.0.0`. |
| `CONTAINER_NAME="app"` | The name of the running container. We use this to find/stop/inspect it. |
| `HEALTH_URL=...` | The URL we'll poll to check the app is alive. |
| `MAX_RETRIES=10` | We'll try the health check up to 10 times. |
| `RETRY_INTERVAL=3` | Wait 3 seconds between attempts. So worst case, 30 seconds before declaring failure — enough time for a slow-starting app. |

### 4b. Record what's currently running (the rollback target)

This is the line that didn't exist before and is the whole reason yesterday's recovery was manual.

```bash
PREVIOUS=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
echo "Current version: $PREVIOUS"
echo "Deploying version: $IMAGE_NAME:$VERSION"
```

**Command breakdown:**

| Component | What it means |
|---|---|
| `docker inspect "$CONTAINER_NAME"` | Returns a giant JSON blob with everything Docker knows about that container. We pass the **container name** (`app`), not the image name — `docker inspect myapp` would fail since `myapp` is the image, not a running thing. |
| `--format='{{.Config.Image}}'` | Instead of the full JSON, just give me the `Image` field nested inside `Config`. The `{{ }}` is Go template syntax — Docker uses it. |
| `$( ... )` | "Run this command and capture its output into a variable." |
| `2>/dev/null` | Throw away any error messages (e.g. if no container exists — first deploy). |
| `\|\| echo "none"` | If the previous command failed (no container existed), output the literal word `none`. So `PREVIOUS` is always set to *something*. |

After this line, `$PREVIOUS` contains either an image tag like `myapp:v1.0.0` or the word `none`. Either way we can use it.

### 4c. Stop the old container, start the new one

```bash
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

docker run -d --name "$CONTAINER_NAME" -p 8080:8080 "$IMAGE_NAME:$VERSION" || true
echo "Started $IMAGE_NAME:$VERSION (or attempted to)"
```

**Command breakdown:**

| Component | What it means |
|---|---|
| `\|\| true` on `docker stop`/`docker rm` | Don't fail the script if these error. They'll error if there's no container to stop, which is fine on a first deploy. Without `\|\| true`, our `set -e` from the top of the script would kill us here. |
| `\|\| true` on `docker run` | **Critical.** If the new image doesn't exist (typo, bad tag, registry down), `docker run` fails. Without `\|\| true` here, `set -e` would kill the script *before* the health check ever runs, meaning the rollback logic below could never trigger. We need this command to be allowed to fail so our error-handling code can do its job. |
| `docker run -d` | `-d` = detached, run in the background. |
| `--name "$CONTAINER_NAME"` | Name the container consistently so we can find it again next deploy. |
| `-p 8080:8080` | Map host port 8080 to container port 8080. |
| `"$IMAGE_NAME:$VERSION"` | The image tag we want — e.g. `myapp:v1.0.0`. |
| `"(or attempted to)"` | Honest wording — the run might have failed silently. The health check is the real verdict on whether we're up. |

### 4d. Health check loop

```bash
echo "Running health checks..."
HEALTHY=false
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        HEALTHY=true
        echo "Health check passed on attempt $i"
        break
    fi
    echo "Health check attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
done
```

**Command breakdown:**

| Component | What it means |
|---|---|
| `HEALTHY=false` | Default to "not healthy" — we only flip this to `true` if a check passes. |
| `for i in $(seq 1 $MAX_RETRIES)` | Loop from 1 to 10, with `$i` as the counter. `seq 1 10` produces `1 2 3 ... 10`. |
| `curl -sf "$HEALTH_URL"` | `-s` = silent (don't print progress). `-f` = fail (return non-zero on HTTP errors like 500). Together: hit the URL quietly, succeed only if we get a 2xx response. |
| `> /dev/null 2>&1` | Throw away both stdout and stderr — we only care about the exit code. |
| `break` | First successful check, exit the loop early. No need to keep checking. |
| `sleep "$RETRY_INTERVAL"` | Wait 3 seconds before trying again. |

**Why retries instead of one check?** The container's process can take a few seconds to bind to its port. A single immediate check almost always fails simply because the app hasn't finished starting. The retry loop is the difference between "this works" and "this is flaky."

### 4e. Decide what to do based on the result

```bash
if [ "$HEALTHY" = true ]; then
    echo "Deployment successful: $IMAGE_NAME:$VERSION"
else
    echo "ERROR: Health check failed after $MAX_RETRIES attempts"
    echo "Rolling back to $PREVIOUS..."

    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    if [ "$PREVIOUS" != "none" ]; then
        docker run -d --name "$CONTAINER_NAME" -p 8080:8080 "$PREVIOUS"
        echo "Rolled back to $PREVIOUS"
    else
        echo "No previous version to rollback to"
    fi
    exit 1
fi
```

**Reasoning:** if the new version is healthy, we're done. If not, run the rollback we planned: stop the broken container, start the previous image we recorded earlier. The `if [ "$PREVIOUS" != "none" ]` covers the edge case where this is the first ever deploy — there's nothing to roll back to. Finally, `exit 1` ensures CI/CD systems and monitoring know the deploy failed.

---

## Step 5 — Write it into `deploy.sh`

Now we assemble sections 4a through 4e into the actual file.

### 5a. Open `deploy.sh` for editing

```bash
vi deploy.sh
```

You'll see the existing broken script. Press `gg` to go to the top, then `dG` to delete everything (or just press `i` and edit as you go — whatever feels natural in vi).

### 5b. Replace the contents

Paste the complete new script below. This is sections 4a → 4b → 4c → 4d → 4e joined together — exactly what should end up in your file:

```bash
#!/bin/bash
set -e

VERSION=${1:?Usage: ./deploy.sh <version>}
IMAGE_NAME="myapp"
CONTAINER_NAME="app"
HEALTH_URL="http://localhost:8080/health"
MAX_RETRIES=10
RETRY_INTERVAL=3

# Record the currently-running version for rollback
PREVIOUS=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
echo "Current version: $PREVIOUS"
echo "Deploying version: $IMAGE_NAME:$VERSION"

# Stop the old container and start the new one
# Note: || true on docker run lets the script continue if the new image
# is missing or broken, so the health check + rollback logic can still
# execute. Without it, set -e would kill the script on a failed pull.
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

docker run -d --name "$CONTAINER_NAME" -p 8080:8080 "$IMAGE_NAME:$VERSION" || true
echo "Started $IMAGE_NAME:$VERSION (or attempted to)"

# Health check loop
echo "Running health checks..."
HEALTHY=false
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        HEALTHY=true
        echo "Health check passed on attempt $i"
        break
    fi
    echo "Health check attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
done

# Decide what to do based on the result
if [ "$HEALTHY" = true ]; then
    echo "Deployment successful: $IMAGE_NAME:$VERSION"
else
    echo "ERROR: Health check failed after $MAX_RETRIES attempts"
    echo "Rolling back to $PREVIOUS..."

    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true

    if [ "$PREVIOUS" != "none" ]; then
        docker run -d --name "$CONTAINER_NAME" -p 8080:8080 "$PREVIOUS"
        echo "Rolled back to $PREVIOUS"
    else
        echo "No previous version to rollback to"
    fi
    exit 1
fi
```

### 5c. Save and exit

In vi: press `Esc` to make sure you're out of insert mode, then type `:wq` and press Enter. (`:w` writes, `:q` quits, `:wq` does both.)

### 5d. Make sure it's executable

```bash
chmod +x deploy.sh
```

You only need to do this once. Once a file has the executable bit set, future edits don't need it again.

### 5e. Sanity-check the contents

Before running, glance at what you saved to make sure it took:

```bash
cat deploy.sh
```

You should see your new script. If you see the old broken one, the save didn't go through — repeat 5a–5c.

---

## Step 6 — Test it

### Test 1: A good deployment

```bash
./deploy.sh v1.0.0
```

Expected output:

```
Current version: myapp:latest
Deploying version: myapp:v1.0.0
app
app
<container ID>
Started myapp:v1.0.0 (or attempted to)
Running health checks...
Health check attempt 1/10 failed, retrying in 3s...
Health check passed on attempt 2
Deployment successful: myapp:v1.0.0
```

The first health check often fails — the Flask app needs a moment to start. Attempt 2 normally passes. This is exactly why we built the retry loop instead of a single check.

Verify:

```bash
docker ps
docker inspect --format='{{.Config.Image}}' app
curl http://localhost:8080
```

You should see `myapp:v1.0.0` is now running and responds.

### Test 2: A bad deployment (the actual rollback test)

The simplest way to trigger the rollback path is to ask the script to deploy an image tag that doesn't exist. The `docker run` will fail, no container will be running, the health check will fail all 10 times, and the rollback will kick in.

```bash
./deploy.sh v-does-not-exist
```

Expected output (this is roughly 30 seconds long because of the 10 × 3s retries):

```
Current version: myapp:v1.0.0
Deploying version: myapp:v-does-not-exist
app
app
Unable to find image 'myapp:v-does-not-exist' locally
docker: Error response from daemon: pull access denied for myapp, ...
Started myapp:v-does-not-exist (or attempted to)
Running health checks...
Health check attempt 1/10 failed, retrying in 3s...
Health check attempt 2/10 failed, retrying in 3s...
... (all 10 fail)
ERROR: Health check failed after 10 attempts
Rolling back to myapp:v1.0.0...
<container ID>
Rolled back to myapp:v1.0.0
```

Verify the rollback worked **and** that the script signalled failure to its caller:

```bash
echo $?    # should print 1
docker ps
docker inspect --format='{{.Config.Image}}' app
curl http://localhost:8080
```

`echo $?` is critical — it returns the exit code of the most recent command. CI/CD pipelines and monitoring use this exit code to decide whether to alert. The deployment ended in a safe state (old version restored), but it still **failed** as a deployment, so we must `exit 1`.

### ⚠ Gotcha: `set -e` vs `|| true` on `docker run`

If you wrote your script without `|| true` on the `docker run` line in the deploy block, this test would have behaved very differently. Instead of seeing the rollback fire, you'd have seen:

```
Current version: myapp:v1.0.0
Deploying version: myapp:v-does-not-exist
app
app
Unable to find image 'myapp:v-does-not-exist' locally
docker: Error response from daemon: pull access denied...
$
```

…and the script would just **exit silently**. No health check, no rollback, no exit code 1, no `app` container running. You'd be left with nothing.

**Why?** Remember `set -e` at the top of the script — "exit immediately on any error." When `docker run` fails, `set -e` kills the script right there, before it ever reaches the health check loop. Our entire rollback design becomes dead code that can never execute.

The fix is `|| true` on the `docker run` line:

```bash
docker run -d --name "$CONTAINER_NAME" -p 8080:8080 "$IMAGE_NAME:$VERSION" || true
```

This says "if `docker run` fails, treat that as a non-error so the script continues." Now control flows naturally into the health check loop, which fails (no container is running), which triggers rollback, exactly as designed.

**The lesson:** `set -e` is a defensive default, but it can have surprising interactions. The places where you *expect* a command might fail — and want to handle that failure yourself — must explicitly opt out with `|| true` (or wrap the command in an `if`). Otherwise your error-handling code is unreachable. This is a real-world bug class in production scripts; it tends to lie dormant for months and only surfaces during an incident.

### Test 3 (optional): First-deploy edge case

What if no container is running yet (e.g. brand new server, or you've stopped/removed everything)? The `PREVIOUS` capture should record `none` and the script should proceed without trying to roll back to nothing.

```bash
docker stop app && docker rm app
./deploy.sh v1.0.0
```

Expected: `Current version: none`, deployment proceeds, health check passes, success. The `if [ "$PREVIOUS" != "none" ]` branch in the rollback block is what would protect us if this deploy *also* failed.

---

## Step 7 — Run the validator

```bash
bash validate.sh
```

All four checks should pass.

---

## Reset (optional, to re-run the lab)

```bash
docker stop app 2>/dev/null
docker rm app 2>/dev/null
git checkout -- deploy.sh
./setup.sh
```

---

## What this looks like in real life

This lab uses Docker on a single host because that's the simplest place to learn the pattern. In production:

- **Kubernetes / ECS** handle most of this for you. `kubectl rollout undo` does what we just built, but for many pods across many nodes, with traffic shifting handled automatically.
- **Blue-green deployments** keep the old version running on a parallel set of containers and only switch traffic after the new version's health checks pass. There's no "old version is gone" gap.
- **Canary deployments** route a small fraction of real user traffic to the new version first. If error rates stay normal, gradually shift more traffic. Catches problems with much lower blast radius.
- **Deployment audit trails** — every deploy gets logged to a system (Datadog, deploy tracker, internal tool) so you can see who deployed what and when.
- **Feature flags** decouple deploying code from releasing features. Deploy with the feature off, turn it on slowly, turn it off instantly if something breaks — no rollback required.

The principles you've just implemented (record-before-deploy, health-check-with-retries, automatic-rollback-on-failure) are the same ones underlying all of those production systems. They're just abstracted away.

---

## Key takeaways

- A deploy script's job isn't done when `docker run` returns — it's done when the app actually responds.
- Always record what's running *before* you change it, or rollback is impossible.
- `latest` is not a version. Use explicit tags so deploys, rollbacks, and audits all work.
- Health checks need retries. Apps don't start instantly.
- Exit codes matter. `exit 1` on failure is how CI/CD pipelines and monitoring know to alert.
- `set -e` and your error-handling code can fight each other. Where you *intend* to handle failure yourself (rollback, retry, fallback), opt out of `set -e` for that command with `|| true` — otherwise your error-handling code is unreachable.

## Common mistakes

- **Health-checking once, immediately.** Almost always fails because the app hasn't bound its port yet. Always retry with a delay.
- **Recording the previous version *after* stopping it.** Too late — `docker inspect` returns nothing once the container is gone. Record first, stop second.
- **Trusting `docker run`'s exit code.** It only tells you the container started. It says nothing about whether the app inside is working.
- **Rolling back without health-checking the rollback.** The previous version could also have problems. Production rollback scripts re-run the same health-check loop after restoring the old version.
- **Hard-coding `latest`.** Means you can't deploy or roll back to anything specific. Always parameterise the version.
- **`set -e` killing the script before rollback can run.** The single most subtle bug class in this lab. If a command is *expected* to potentially fail (like deploying a bad version), you must explicitly tolerate that failure with `|| true`. Otherwise `set -e` kills the script and your rollback logic is dead code.
