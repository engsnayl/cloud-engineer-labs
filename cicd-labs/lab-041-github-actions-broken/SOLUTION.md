# Lab 041 — GitHub Actions Debugging: Solution Walkthrough

---

## TLDR — What's Going On Here (Plain English)

You've been handed a CI/CD pipeline — basically a set of automated instructions that runs every time code changes. Think of it like a conveyor belt in a factory: code goes in one end, gets tested, and if it passes, gets deployed automatically.

This pipeline is broken. Not spectacularly broken — it won't throw a giant red error at you. It has four bugs that either silently do nothing, or worse, do the wrong thing at the wrong time.

**Here's what's wrong, in plain English:**

1. A job has a space in its name — which breaks how other jobs find it
2. A step tries to set a variable but uses the wrong method — so the variable evaporates immediately
3. The deploy job runs even on unfinished, unreviewed code — dangerous
4. One job tries to wait for another job to finish, but points to a name that doesn't exist

Your job is to find each of these, understand *why* they're broken, and fix them — the same way you'd approach it as a real engineer on-call.

---

## What Is GitHub Actions, and Why Should You Care?

Before we touch any bugs — a quick orientation.

**GitHub Actions** is GitHub's built-in automation system. You write instructions in a YAML file (a structured text file that uses indentation to show hierarchy) and GitHub runs those instructions automatically whenever something happens — like code being pushed or a pull request being opened.

These instructions are called **workflows**. A workflow is made up of **jobs** (big chunks of work), and each job is made up of **steps** (individual commands).

```
Workflow
  └── Job: build-and-test
        ├── Step: Check out code
        ├── Step: Install dependencies
        └── Step: Run tests
  └── Job: deploy
        └── Step: Push to production
  └── Job: notify
        └── Step: Send notification
```

**Why does this matter for your career?** Almost every engineering team uses CI/CD. Knowing how to read, debug, and fix pipelines is a core skill. This lab is your first hands-on exposure to it.

---

## Starting the Lab — What You're Looking At

When you navigate to the lab directory, `ls` will show you this:

```
CHALLENGE.md  HINTS.md  package.json  SOLUTION.md  validate.sh
```

You might wonder: where's the broken workflow file I'm supposed to fix?

The workflow file lives in a hidden folder. In Linux, any folder or file that starts with a `.` (dot) is hidden from a standard `ls`. To see hidden files, use:

```bash
ls -la
```

You'll now see `.github/` in the list. The broken workflow file is at:

```
.github/workflows/ci.yml
```

**Important:** `.github/` is not just a convention — it's the exact folder name GitHub looks for when running Actions. It must be spelled exactly like this, including the dot.

### Command breakdown — ls flags

| Part | What it means |
|------|--------------|
| `ls` | List files in the current directory |
| `-l` | Long format — show permissions, size, owner, date |
| `-a` | All files — include hidden files and folders (those starting with `.`) |
| `-la` | Both flags combined — long format, including hidden files |

---

## The Broken Workflow File — Starting State

Before fixing anything, open the file and read it:

```bash
cat .github/workflows/ci.yml
```

You should see:

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build and test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set environment
        run: echo "NODE_ENV=test"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

  deploy:
    needs: build and test
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          echo "Deploying..."

  notify:
    needs: build-and-test
    runs-on: ubuntu-latest
    steps:
      - name: Notify
        run: echo "Pipeline complete"
```

Don't fix anything yet. Read it first. Can you spot the four problems before looking at the solutions below?

---

## Running the Validator

This lab has a validation script that checks your fixes:

```bash
bash validate.sh
```

Before fixing anything, run it to see the baseline — all failing:

```
Running validation checks...
  ✅  Job names use valid characters (no spaces)
  ❌  Environment variables use GITHUB_ENV
  ❌  Deploy step has conditional (not running on PRs)
  ❌  Job dependency name matches actual job
Results: 1 passed, 3 failed
```

### A note on the validator — Check 1 has a flaw

You'll notice check 1 shows green even though `build and test:` clearly has spaces in its name. This is a bug in the validator itself.

The validator checks for this pattern:

```bash
grep -E "^  [a-z][a-z0-9_-]+:" "$WORKFLOW"
```

What this actually does: it looks for *any* line that starts with two spaces, a lowercase letter, then valid characters. Because `deploy:` and `notify:` are valid job names, they match — so the check passes even though `build and test:` is broken.

**What this means for you:** Don't trust check 1 as a signal. The bug still needs fixing — the validator just can't catch it properly. Your real target is all 4 checks passing, which requires fixing all 4 bugs including the job name.

---

## The Four Bugs — Investigative Pathway

Work through these in order. Each one is a discovery process, not just a fix.

---

### Bug 1: The Job Name Has Spaces

#### What symptom tells you something is wrong?

Look at the `notify` job at the bottom of the file:

```yaml
notify:
  needs: build-and-test
```

This means "don't run notify until `build-and-test` finishes." But there is no job called `build-and-test` — the actual job is called `build and test` (with spaces). GitHub can't find the dependency. The notify job either won't run or will behave unpredictably.

Also look at the `deploy` job:

```yaml
deploy:
  needs: build and test
```

This `needs:` reference also has spaces — for the same reason, this dependency is broken too.

#### Why does this happen?

YAML files use the text before the `:` as a **key** — like a label in a filing cabinet. GitHub Actions uses these keys to wire jobs together. A key with spaces can't be referenced reliably from other parts of the file.

#### How do you find it?

Open `.github/workflows/ci.yml` and scan the `jobs:` section. Every job name sits at the same indentation level, followed by a colon. Look for spaces in those names.

```yaml
jobs:
  build and test:    # ← Spaces in the job key
    runs-on: ubuntu-latest
```

#### What's the fix?

Replace spaces with hyphens in the job name:

```yaml
# BROKEN
jobs:
  build and test:
    runs-on: ubuntu-latest

# FIXED
jobs:
  build-and-test:
    runs-on: ubuntu-latest
```

#### Command breakdown

| Part | What it means |
|------|--------------|
| `jobs:` | The section of the file that lists all jobs in this workflow |
| `build-and-test:` | The **key** (name) of this job — must be a single word, no spaces |
| `runs-on: ubuntu-latest` | Tells GitHub what type of machine to run this job on |

> **Useful to know:** You can also use underscores: `build_and_test`. Hyphens are the most common convention you'll see in the wild.

---

### Bug 2: The Environment Variable Isn't Being Saved

#### What symptom tells you something is wrong?

There's a step that appears to set `NODE_ENV=test`. But any step that comes *after* it and tries to use `$NODE_ENV` will find it empty. The variable was never actually saved — it was printed to the screen and thrown away.

#### Why does this happen?

In GitHub Actions, each `run:` step opens a brand new shell (a fresh terminal session). Variables set in one shell **die when that shell closes**. So `echo "NODE_ENV=test"` only exists for the fraction of a second that echo command runs. The next step starts with a completely fresh shell and no memory of it.

GitHub Actions provides a special mechanism for this: a file called `$GITHUB_ENV`. If you write a variable into that file, GitHub reads it before each subsequent step and makes it available.

#### How do you find it?

Look for a step that sets an environment variable using just `echo`:

```yaml
- name: Set environment
  run: echo "NODE_ENV=test"
```

Ask yourself: where is this output going? `echo` prints to the screen. It doesn't write anywhere that persists. Nothing survives past this step.

#### What's the fix?

Redirect the output into the `$GITHUB_ENV` file using `>>`:

```yaml
# BROKEN
- name: Set environment
  run: echo "NODE_ENV=test"

# FIXED
- name: Set environment
  run: echo "NODE_ENV=test" >> $GITHUB_ENV
```

#### Command breakdown

| Part | What it means |
|------|--------------|
| `echo` | Print text to the screen (or to a file, if redirected) |
| `"NODE_ENV=test"` | The text being printed — a key=value pair |
| `>>` | **Append** operator — adds to the end of a file without overwriting it |
| `$GITHUB_ENV` | A special file GitHub provides. Anything written here as `KEY=value` becomes an environment variable for all following steps in the job |

> **Useful to know:** `>` would also work (it overwrites instead of appending), but `>>` is safer when multiple variables are being set — it won't erase earlier ones.

---

### Bug 3: The Deploy Job Runs on Pull Requests

#### What symptom tells you something is wrong?

This one won't show as an error — it'll show as a catastrophe. Every time someone opens a pull request (a request to review code before merging it), the deploy job will run and push that unreviewed code to production.

Pull requests exist so code can be reviewed *before* it goes live. Deploying from a PR completely defeats the purpose.

#### Why does this happen?

Look at the top of the workflow file:

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

This means the whole workflow triggers on both pushes *and* pull requests. Individual jobs can add an `if:` condition to restrict when they run. Without one, a job runs for every trigger event — including PRs.

#### How do you find it?

Look at the deploy job. Does it have an `if:` condition? If not, it runs unconditionally on everything.

```yaml
deploy:
  needs: build-and-test
  runs-on: ubuntu-latest
  # No if: condition — deploys on PRs too
  steps:
    ...
```

#### What's the fix?

Add an `if:` condition that checks two things: the event was a push (not a PR), and the branch is `main`.

```yaml
# BROKEN
deploy:
  needs: build-and-test
  runs-on: ubuntu-latest

# FIXED
deploy:
  needs: build-and-test
  runs-on: ubuntu-latest
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

#### Command breakdown

| Part | What it means |
|------|--------------|
| `if:` | A condition — this job only runs if the expression evaluates to `true` |
| `github.event_name` | A built-in variable containing what triggered the workflow (`push`, `pull_request`, etc.) |
| `== 'push'` | Checks whether the trigger was a push event |
| `&&` | Logical AND — both conditions must be true for the job to run |
| `github.ref` | A built-in variable containing the full branch reference (e.g. `refs/heads/main`) |
| `== 'refs/heads/main'` | Checks whether we're on the main branch |

> **Useful to know:** `github.event_name` and `github.ref` are part of the **GitHub Actions context** — a set of built-in variables that are always available in every workflow. You don't define them; GitHub provides them automatically.

---

### Bug 4: The Job Dependency Points to a Name That Doesn't Exist

#### What symptom tells you something is wrong?

The `notify` job uses `needs: build-and-test`. This means "wait for `build-and-test` to finish before running." But the actual job in this file is called `build and test` (with spaces) — so the reference points to a job that doesn't exist.

The `deploy` job has the same problem: `needs: build and test` — also broken for the same reason.

#### Why does this happen?

The `needs:` field creates a dependency link between jobs. GitHub has to trace that link back to an exact job key. If there's any mismatch — spaces, capitalisation, hyphens — the link breaks. GitHub Actions is not forgiving about this.

#### How do you find it?

After fixing Bug 1 (renaming the job to `build-and-test`), scan every `needs:` reference in the file and check that it points to a job key that now exists.

```yaml
notify:
  needs: build-and-test    # Does a job called exactly "build-and-test" now exist?
```

After fixing Bug 1, yes. Bug 4 resolves itself once Bug 1 is fixed — as long as you update both `needs:` references (in `deploy` and `notify`) to match the new name.

#### Verification

After all fixes, check the YAML parses cleanly:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```

If no output appears, the YAML is valid. If you see an error, there's a syntax problem to fix first.

| Part | What it means |
|------|--------------|
| `python3 -c` | Run a Python command directly from the terminal (no script file needed) |
| `import yaml` | Load Python's YAML parsing library |
| `yaml.safe_load(...)` | Attempt to parse the file — errors mean broken YAML syntax |
| `open('.github/workflows/ci.yml')` | Open the workflow file for parsing |

> **Useful to know:** This only validates YAML structure — it can't check GitHub Actions logic. `actionlint` is a dedicated linter that understands GitHub Actions semantics. Worth knowing it exists, even if you don't install it on the Pi right now.

---

## The Fixed File — What It Should Look Like

After all four fixes, your file should look exactly like this:

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set environment
        run: echo "NODE_ENV=test" >> $GITHUB_ENV

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Deploy
        run: |
          echo "Deploying..."

  notify:
    needs: build-and-test
    runs-on: ubuntu-latest
    steps:
      - name: Notify
        run: echo "Pipeline complete"
```

Run the validator to confirm:

```bash
bash validate.sh
```

Expected output:

```
Running validation checks...
  ✅  Job names use valid characters (no spaces)
  ✅  Environment variables use GITHUB_ENV
  ✅  Deploy step has conditional (not running on PRs)
  ✅  Job dependency name matches actual job
Results: 4 passed, 0 failed
```

---

## Lab Repeatability

**Do not commit the fixed file.** The broken state in the repo is the starting point for every future attempt.

When you want to repeat the lab:

```bash
# Discard your local fixes and restore the broken version from the repo
git checkout -- .github/workflows/ci.yml
```

| Part | What it means |
|------|--------------|
| `git checkout` | Restore files to a previous state |
| `--` | Signals that what follows is a file path, not a branch name |
| `.github/workflows/ci.yml` | The specific file to restore |

This pulls the broken version back from the repo without touching anything else.

---

## Pi / Environment Notes

- **Hidden folders:** The `.github/` directory is hidden by default. Always use `ls -la` rather than `ls` when you're not sure what's in a directory.
- **act (local GitHub Actions runner):** The CHALLENGE.md mentions `act` as an optional testing tool. On ARM64 Pi, this is not worth setting up for this lab. The validator script is sufficient. `act` becomes more relevant in later labs where you're writing pipelines from scratch and need fast iteration.
- **YAML is indentation-sensitive:** One wrong space in the YAML file will break it. If the validator fails unexpectedly, `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` will tell you if there's a syntax error.

---

## Real World Context

- **Branch protection rules** enforce that CI must pass before any PR can be merged. Without this, engineers can push broken code to main.
- **GitHub Environments** add a human approval gate — a person must click approve before the deploy job runs. Combined with `if:` conditions, this is defence in depth.
- **Secrets rotation** — credentials that never change are a security risk. Most production teams use short-lived credentials via IAM roles (OIDC) rather than long-lived access keys.
- **`actionlint`** is a linter specifically for GitHub Actions workflow files. Unlike YAML validators, it understands GitHub Actions semantics — it can catch `needs:` mismatches, invalid context references, and deprecated syntax.
- **Reusable workflows** (`workflow_call`) let large organisations define a standard pipeline once and share it across all repositories. Each team uses it without reinventing the wheel.

---

## Key Concepts Summary

| Concept | One-Line Explanation |
|---------|----------------------|
| Job key | The name of a job in the workflow — must use hyphens or underscores, not spaces |
| `$GITHUB_ENV` | A special file — write `KEY=value` to it to persist variables between steps |
| `if:` condition | Controls when a job runs — essential for deploy jobs |
| `github.event_name` | Built-in variable — what triggered the workflow |
| `github.ref` | Built-in variable — which branch the code is on |
| `needs:` | Declares that one job must wait for another — must match the job key exactly |
| `ls -la` | Lists all files including hidden ones — essential when working with `.github/` |

---

## Common Mistakes

- **Spaces in job names** — Always use hyphens. Spaces silently break dependency references and the validator may not catch it.
- **Forgetting `>> $GITHUB_ENV`** — `echo "VAR=value"` on its own does nothing useful for subsequent steps.
- **No `if:` condition on deploy** — The #1 cause of accidental production deployments from unreviewed PRs.
- **`needs:` mismatch after renaming** — If you rename a job, you must update every `needs:` that references it. Easy to miss if there are multiple jobs depending on it.
- **Not using `ls -la`** — Standard `ls` hides dotfiles. Always use `-la` when you're unsure what's in a directory.
- **Committing the fix** — The repo should always hold the broken state. Use `git checkout -- .github/workflows/ci.yml` to restore it if needed.
