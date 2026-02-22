# Solution Walkthrough — GitHub Actions Debugging

## The Problem

A GitHub Actions CI/CD pipeline is failing. The workflow file has **five bugs** that prevent jobs from running correctly:

1. **Job name contains spaces** — the job is named `"build and test"` but YAML job keys can't have spaces. GitHub Actions silently fails or can't reference the job correctly.
2. **Environment variable not persisted** — `echo "NODE_ENV=test"` prints to stdout but doesn't set the variable for subsequent steps. Must use `>> $GITHUB_ENV` to persist across steps.
3. **Deploy runs on pull requests** — the deploy job triggers on every event including PRs, which means untested code could deploy to production from a PR.
4. **Missing secrets environment variables** — the deploy step references AWS credentials but doesn't map them from `secrets` to environment variables.
5. **Job dependency references wrong name** — the `notify` job uses `needs: build-and-test` but the actual job key doesn't match (due to the spaces bug), so the dependency can't resolve.

## Thought Process

When a GitHub Actions workflow fails, an experienced engineer checks:

1. **YAML syntax** — job names must be valid YAML keys (no spaces). Steps must have correct indentation and structure.
2. **Environment variables** — `$GITHUB_ENV` is the only way to persist env vars between steps in the same job. Plain `echo` doesn't set anything.
3. **Conditional execution** — deploy jobs should only run on pushes to main, not on PRs. Use `if:` conditions to control when jobs execute.
4. **Job dependencies** — `needs:` must reference the exact job key. If the key doesn't match, the dependency graph is broken and the job won't run.

## Step-by-Step Solution

### Step 1: Fix the job name — remove spaces

Open `.github/workflows/ci.yml` and find the job key with spaces.

```yaml
# BROKEN
jobs:
  build and test:    # Spaces in job name!
    runs-on: ubuntu-latest

# FIXED
jobs:
  build-and-test:    # Hyphens instead of spaces
    runs-on: ubuntu-latest
```

**What this does:** GitHub Actions job keys are YAML mapping keys. Spaces make the key ambiguous and break references from other jobs. Using hyphens (`build-and-test`) follows the standard convention and allows other jobs to reference it with `needs: build-and-test`.

### Step 2: Fix the environment variable persistence

```yaml
# BROKEN
- name: Set environment
  run: echo "NODE_ENV=test"    # Prints to stdout, doesn't set anything

# FIXED
- name: Set environment
  run: echo "NODE_ENV=test" >> $GITHUB_ENV    # Persists for subsequent steps
```

**What this does:** In GitHub Actions, each `run` step executes in a fresh shell. To pass environment variables between steps, you must append them to `$GITHUB_ENV`. The format is `KEY=value` written to that special file. Without `>> $GITHUB_ENV`, the variable only exists during that single `echo` command and is lost immediately.

### Step 3: Add conditional to the deploy job — only on push to main

```yaml
# BROKEN
  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    # No condition — runs on PRs too!

# FIXED
  deploy:
    needs: build-and-test
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

**What this does:** The `if:` condition ensures the deploy job only runs when code is pushed directly to `main` (or merged via PR). Without it, opening a PR would trigger a deployment — dangerous because the code hasn't been reviewed or merged yet. The condition checks two things: the event type is a push (not a PR), and the branch is main.

### Step 4: Add secrets as environment variables to the deploy step

```yaml
# BROKEN
    steps:
      - name: Deploy
        run: |
          echo "Deploying..."
          # No AWS credentials available!

# FIXED
    steps:
      - name: Deploy
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          echo "Deploying..."
```

**What this does:** GitHub Actions secrets are not automatically available as environment variables — you must explicitly map them using the `env:` block. The `${{ secrets.SECRET_NAME }}` syntax reads the value from the repository's encrypted secrets store and injects it into the step's environment. Without this mapping, AWS CLI commands would fail with "Unable to locate credentials."

### Step 5: Fix the notify job dependency

```yaml
# BROKEN
  notify:
    needs: build-and-test    # Must match the actual job key exactly
    runs-on: ubuntu-latest

# FIXED (this works now that Step 1 fixed the job name)
  notify:
    needs: build-and-test    # Matches the fixed job key
    runs-on: ubuntu-latest
```

**What this does:** The `needs:` field creates a dependency — the notify job waits for `build-and-test` to complete. The referenced name must exactly match a job key defined in the `jobs:` section. Once Step 1 fixes the job name to `build-and-test`, this reference resolves correctly.

### Step 6: Validate

```bash
# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

# Or use actionlint if available
actionlint .github/workflows/ci.yml
```

## Docker Lab vs Real Life

- **Branch protection rules:** In production, configure GitHub branch protection to require the CI workflow to pass before merging. This ensures broken code never reaches main.
- **Reusable workflows:** Large organizations use reusable workflows (`workflow_call`) to standardize CI across repositories. Each team doesn't reinvent the pipeline.
- **Environment protection rules:** GitHub Environments add approval gates — a human must approve before the deploy job runs. Combine with `if:` conditions for defense in depth.
- **Caching:** Production workflows use `actions/cache` to cache `node_modules`, Docker layers, and build artifacts. This cuts CI time from minutes to seconds.
- **Matrix builds:** Test across multiple Node.js versions, OS combinations, or dependency sets using `strategy.matrix`. One workflow file covers all combinations.

## Key Concepts Learned

- **Job keys can't have spaces** — use hyphens or underscores. Spaces break YAML key references and `needs:` dependencies.
- **`$GITHUB_ENV` persists variables between steps** — `echo "KEY=value" >> $GITHUB_ENV` is the only way to share env vars across steps in the same job.
- **Deploy jobs need `if:` conditions** — always guard deployments with `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` to prevent accidental deploys from PRs.
- **Secrets must be explicitly mapped** — `${{ secrets.NAME }}` injects secrets into `env:` blocks. They're never available automatically.
- **`needs:` must match exact job keys** — dependency references are string-exact. A typo or mismatch silently breaks the workflow graph.

## Common Mistakes

- **Spaces in job names** — YAML allows quoted keys with spaces, but GitHub Actions job references break. Always use hyphens.
- **Forgetting `>> $GITHUB_ENV`** — `echo "VAR=value"` does nothing useful. The `>>` append operator is critical.
- **Deploying from PRs** — without an `if:` condition, the deploy job runs on every trigger event. This is the #1 cause of accidental production deployments.
- **Hardcoding secrets** — never put credentials directly in the workflow file. Always use `${{ secrets.NAME }}` from the repository's secrets settings.
- **Case sensitivity in `needs:`** — `Build-And-Test` is not the same as `build-and-test`. Job keys are case-sensitive.
