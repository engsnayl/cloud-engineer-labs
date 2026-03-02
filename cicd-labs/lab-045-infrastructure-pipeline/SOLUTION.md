# Solution Walkthrough — Infrastructure Pipeline (Terraform in CI/CD)

## The Problem

A junior engineer ran `terraform apply` locally and broke production. The team needs a proper CI/CD pipeline for Terraform to prevent unauthorized changes. The GitHub Actions workflow (`.github/workflows/terraform.yml`) has **five bugs**:

1. **No `terraform init`** — the workflow runs plan/apply without initializing Terraform first. Providers aren't downloaded, backend isn't configured, and modules aren't fetched.
2. **Apply runs on every trigger** — `terraform apply` runs on PRs as well as pushes to main. This means opening a PR could apply infrastructure changes to production.
3. **No plan output on PRs** — when a PR is opened, the team can't see what Terraform will change. There's no plan step that outputs the diff for review.
4. **No formatting or validation** — `terraform fmt -check` and `terraform validate` aren't run. Poorly formatted or syntactically invalid code can be merged.
5. **No state locking configuration** — concurrent pipeline runs could corrupt the Terraform state file.

## Thought Process

When setting up Terraform in CI/CD, an experienced engineer ensures:

1. **Init before everything** — `terraform init` must run before any other Terraform command. It downloads providers, initializes the backend, and fetches modules.
2. **Plan on PR, apply on merge** — PRs should only run `terraform plan` and post the output as a comment. `terraform apply` only runs after the PR is merged to main.
3. **Formatting and validation** — `terraform fmt -check` catches style issues. `terraform validate` catches syntax errors. Both should run early and fail fast.
4. **State locking** — configure DynamoDB or similar for state locking to prevent concurrent modifications. This is configured in the backend, not the workflow, but the workflow should not use `-lock=false`.

## Step-by-Step Solution

### Step 1: Add terraform init

Every Terraform workflow must initialize before running any commands.

```yaml
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init
```

**What this does:** `terraform init` performs three critical setup tasks:
- Downloads provider plugins (AWS, GCP, Azure, etc.)
- Configures the backend (S3, GCS, etc.) for state storage
- Downloads referenced modules

Without init, every subsequent Terraform command fails with "provider not found" or "backend not initialized" errors.

### Step 2: Add formatting and validation checks

```yaml
      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate
```

**What this does:** `terraform fmt -check` verifies all `.tf` files follow the canonical formatting style. The `-check` flag makes it exit with an error if any files need formatting (instead of reformatting them). `terraform validate` checks the configuration for internal consistency — correct resource types, valid attribute names, proper references. These are fast checks that catch obvious mistakes before the expensive plan step.

### Step 3: Run plan on pull requests

```yaml
      - name: Terraform Plan
        if: github.event_name == 'pull_request'
        run: terraform plan -no-color -out=tfplan
        continue-on-error: true

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            `;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });
```

**What this does:** On pull requests, the workflow runs `terraform plan` and posts the output as a PR comment. This lets reviewers see exactly what infrastructure changes will happen before approving. The `-out=tfplan` saves the plan file so the exact same plan can be applied later (preventing drift between plan and apply). `-no-color` strips ANSI color codes that don't render in PR comments.

### Step 4: Apply only on push to main

```yaml
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve tfplan
```

**What this does:** `terraform apply` only runs when code is pushed to the main branch (which happens when a PR is merged). The `if:` condition prevents apply from running on PRs. The `-auto-approve` flag is safe here because the plan was already reviewed as part of the PR process. Using the saved plan file (`tfplan`) ensures exactly what was reviewed gets applied — no surprise changes.

### Step 5: The complete fixed workflow

```yaml
name: Terraform CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color
        continue-on-error: true

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve
```

### Step 6: Validate

```bash
# Check init is present
grep -q "terraform init" .github/workflows/terraform.yml

# Check plan is present
grep -q "terraform plan" .github/workflows/terraform.yml

# Check validate or fmt is present
grep -qE "terraform (validate|fmt)" .github/workflows/terraform.yml

# Check apply is conditional
grep -A2 "terraform apply" .github/workflows/terraform.yml | grep -q "if:"
```

## Docker Lab vs Real Life

- **Remote state with locking:** Production Terraform uses S3 + DynamoDB backend for state storage and locking. This prevents two pipeline runs from modifying state simultaneously.
- **Separate plan and apply jobs:** Some teams split plan and apply into separate workflow jobs. The plan job produces an artifact, and the apply job (triggered by approval) uses that exact artifact.
- **Environment-specific workflows:** Production pipelines deploy to dev first, then staging, then production. Each environment has its own Terraform workspace or directory and requires separate approvals.
- **Drift detection:** Schedule a cron job to run `terraform plan` nightly. If it detects changes (someone made manual console changes), alert the team. This catches configuration drift.
- **Cost estimation:** Tools like Infracost integrate into the PR workflow to show the cost impact of infrastructure changes before they're approved.
- **Policy as code:** Use OPA (Open Policy Agent) or Sentinel to enforce policies like "no public S3 buckets" or "all EC2 instances must be tagged." These run before apply and block non-compliant changes.

## Key Concepts Learned

- **`terraform init` must run first** — it downloads providers, configures the backend, and fetches modules. Without it, nothing works.
- **Plan on PR, apply on merge** — the fundamental CI/CD pattern for infrastructure. Reviewers see the plan, approve the PR, and only then does apply run.
- **`terraform fmt -check` and `validate` catch early errors** — formatting issues and syntax errors are caught before the expensive plan step.
- **`if:` conditions control when jobs run** — `github.event_name == 'push' && github.ref == 'refs/heads/main'` ensures apply only runs after merge to main.
- **State locking prevents corruption** — concurrent applies can corrupt state. Always configure backend locking (DynamoDB for S3, built-in for Terraform Cloud).

## Common Mistakes

- **Forgetting `terraform init`** — the most common Terraform CI/CD mistake. Without init, the pipeline fails immediately with cryptic provider errors.
- **Running apply on PRs** — this applies untested, unreviewed changes to production. Apply must only run on pushes to the main branch.
- **No plan output for review** — if reviewers can't see what will change, they're approving blind. Always post the plan to the PR.
- **Using `-lock=false`** — this disables state locking, which "fixes" concurrency errors but creates a much worse problem: state corruption. Fix the locking configuration instead.
- **Running `terraform apply` without the plan file** — between plan and apply, the infrastructure state could change. Applying a saved plan file ensures consistency. Without it, the apply might do something different from what was reviewed.
