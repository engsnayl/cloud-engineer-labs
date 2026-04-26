# Lab 045 — IaC Pipeline (Terraform in CI/CD)

## TLDR (Plain English)

A junior engineer ran Terraform on their laptop and broke production. The team's response was to build a pipeline so that nobody can apply infrastructure changes from their laptop ever again — every change has to go through GitHub, get reviewed, and only then get applied.

The problem: the pipeline they've built is broken. It doesn't set Terraform up before using it, it applies changes the moment anyone opens a pull request (which is the *opposite* of what they wanted), it doesn't show reviewers what the changes will do, and it doesn't check the code is properly written before running it.

The fix: rebuild the pipeline so that **on a pull request** it does safe read-only checks (formatting, validation, and a preview of the changes), and **only when code is merged into the main branch** does it actually apply those changes. Five fixes in one YAML file. About 20 minutes of work once you understand what you're looking at.

---

## The Ticket

```
INCIDENT-CICD-005

Junior engineer ran terraform apply locally and broke production.
Need a CI pipeline that enforces plan review before apply.
No more local applies.
```

That's everything you've been given. No mention of which file is broken, no list of what's wrong with it, no reproduction steps. Just an incident reference and a goal.

---

## What is GitHub Actions, actually?

Before we open any files, a quick orientation — because if you've not worked with GitHub Actions before, the syntax is going to look like noise.

**GitHub Actions** is GitHub's built-in CI/CD system. Whenever something happens in your repository — someone pushes code, opens a pull request, merges a branch — GitHub can automatically run scripts on virtual machines on your behalf. Those scripts can do anything: run tests, build Docker images, deploy to AWS, run Terraform. The instructions for what to run live in YAML files inside `.github/workflows/`.

The anatomy of a workflow file:

| Block | What it does |
|---|---|
| `name:` | Human-readable name shown in the GitHub UI |
| `on:` | The triggers — what events cause this workflow to run (push, pull_request, schedule, etc.) |
| `jobs:` | One or more units of work. Each job runs on its own fresh virtual machine. |
| `runs-on:` | The type of virtual machine to use (`ubuntu-latest` is the standard) |
| `steps:` | The ordered list of things to do inside a job |
| `uses:` | Pulls in a pre-built reusable component (called an "action") from the marketplace |
| `run:` | Executes a shell command directly |
| `if:` | A condition that decides whether the step runs at all |

A "runner" is the virtual machine GitHub spins up to execute your job. It starts with nothing on it — a clean Ubuntu install — so anything you need (Terraform, AWS CLI, Node, etc.) has to be installed by an early step in the workflow.

That's the whole mental model. Workflow file describes triggers and steps, GitHub spins up a fresh VM when a trigger fires, runs the steps in order, throws the VM away when done.

---

## Step 1 — Arrive at the scene

You've been given an incident ticket and that's it. First thing any engineer does on a CI/CD ticket: find the pipeline file.

```bash
cd cicd/lab-045-terraform-iac-pipeline
ls -la
```

Then locate the workflow:

```bash
find . -name "*.yml" -path "*/workflows/*"
```

That should turn up `.github/workflows/terraform.yml`. Open it.

```bash
cat .github/workflows/terraform.yml
```

What you see:

```yaml
# Terraform CI/CD Pipeline
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3

    - name: Terraform Apply
      run: terraform apply -auto-approve
```

Read it top to bottom. Don't try to spot bugs yet — just understand what it's saying.

**What this workflow currently does:**
- Triggers on pushes to main, and on pull requests targeting main
- Spins up an Ubuntu runner
- Checks out the code
- Installs Terraform
- Runs `terraform apply -auto-approve`

That's the entire pipeline.

---

## Step 2 — First red flag: where's the setup?

Now read it as if you were the engineer who has to make this work. The third step says `terraform apply`. Pause there.

**What does `terraform apply` actually need to function?** It needs:
1. Provider plugins downloaded (the AWS provider, for example, isn't bundled with Terraform — it's a separate binary that has to be fetched)
2. The backend configured (where state is stored and locked)
3. Any referenced modules pulled down

All three of those things are done by **`terraform init`**. And `terraform init` is nowhere in this file.

**How would I know this?** Two ways:
- If you've ever run Terraform locally, you know `init` is the first thing you do in a fresh directory. The error message you get if you skip it is unmistakeable: *"Could not load plugin... Initialization required."*
- If you haven't, then reading the workflow and asking "what would this VM actually have on it?" gets you there. The runner is a fresh Ubuntu box. `setup-terraform@v3` puts the Terraform binary on the PATH — but that's just the binary. It doesn't know anything about your code, your providers, or your backend.

**The fix:** add a `Terraform Init` step before any other Terraform command runs.

```yaml
    - name: Terraform Init
      run: terraform init
```

That step goes after `setup-terraform` (you need the binary before you can run `init`) and before everything else.

**Sanity check after the fix:** if you mentally walk through the runner's day — fresh Ubuntu boots, code gets checked out, Terraform binary gets installed, init pulls down providers and configures the backend, *then* the apply step has everything it needs — does it work end-to-end? Yes. Move on.

---

## Step 3 — The dangerous one: when does apply run?

Now look at the `on:` block at the top of the file and the apply step at the bottom together.

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

```yaml
    - name: Terraform Apply
      run: terraform apply -auto-approve
```

The workflow triggers on **two** events: a push to main, *and* a pull request to main. The apply step has no `if:` condition on it, which means it runs **every time the workflow triggers**.

Read what that actually means in plain English: *every time anyone opens a pull request, Terraform applies their unreviewed changes to production*.

That is the **exact problem the ticket is asking you to fix**. The whole point of putting Terraform into CI/CD is to prevent unreviewed applies. This pipeline does the opposite.

**Diagnostic pathway:**
1. **What do I see?** An apply step with no condition, on a workflow that triggers on PRs.
2. **Why is that wrong?** Because the ticket explicitly says "enforce plan review before apply" — applying on PRs is the opposite of that.
3. **What's the principle?** *Plan on PR, apply on merge.* The PR is for review. The merge to main is the signal that review is complete.
4. **How do I express "only run on push to main" in GitHub Actions?** Two conditions, joined with `&&`:
   - `github.event_name == 'push'` — the trigger was a push, not a pull request
   - `github.ref == 'refs/heads/main'` — the branch is main
5. **Where does the condition go?** On the apply step itself, as an `if:` key.

**The fix:**

```yaml
    - name: Terraform Apply
      if: github.event_name == 'push' && github.ref == 'refs/heads/main'
      run: terraform apply -auto-approve
```

### Command breakdown — the `if:` condition

| Component | What it means |
|---|---|
| `if:` | Tells GitHub Actions "only run this step if the following expression is true" |
| `github.event_name` | A built-in variable holding the event that triggered the workflow (`push`, `pull_request`, etc.) |
| `== 'push'` | String comparison — true only if the trigger was a push |
| `&&` | Logical AND — both sides must be true for the whole expression to be true |
| `github.ref` | A built-in variable holding the Git ref the workflow is running against |
| `'refs/heads/main'` | The full ref name for the main branch (GitHub uses the long form internally) |

**Why both checks?** `github.event_name == 'push'` alone isn't enough — someone could push to a feature branch and the workflow would still run on it (well, it wouldn't here because `on: push` is scoped to main, but it's defensive practice). `github.ref == 'refs/heads/main'` alone isn't enough either, because a pull request targeting main also has `github.ref` related to main in some contexts. Belt and braces — both conditions together mean "this is a real merge to main, not anything else."

---

## Step 4 — What about the PRs? Where's the plan?

You've made apply safe. But the ticket says "enforce plan review" — meaning when someone opens a PR, the reviewer should be able to see *what Terraform is going to change* before they approve.

**Diagnostic pathway:**
1. **What do I see in the current workflow?** No plan step at all. PRs trigger the workflow, but the workflow now does nothing useful on a PR (apply is now correctly skipped).
2. **What should happen on a PR?** `terraform plan` should run and show the diff — what resources will be created, modified, or destroyed.
3. **Where should this go?** Before the apply step, with its own `if:` condition limiting it to PRs (and ideally also pushes, so you have a record of the plan that was applied).
4. **How does the reviewer see it?** Two options: read the GitHub Actions log directly (works fine, slightly clunky), or post the plan output as a comment on the PR (much nicer review UX). For this lab we'll add a simple plan step — posting to the PR as a comment is a polish step covered in "Real-World Extensions."

**The fix:**

```yaml
    - name: Terraform Plan
      run: terraform plan
```

That step goes between init and apply. It runs on every trigger — which is correct. On a PR, the plan output appears in the workflow log and the reviewer can read it before approving the merge. On a push to main, plan runs again immediately before apply, giving you a final record in the log of exactly what's about to be applied.

---

## Step 5 — Catching mistakes early: fmt and validate

Last gap. Look at where init currently is — it's the first Terraform step. But init does real work: it makes network calls to download providers, talks to the backend (S3/DynamoDB in real life), pulls modules. It's not free.

**Question:** what if the Terraform code in the PR has a typo or is badly formatted? Right now, init runs first, plan runs second, and only at plan time does Terraform notice the syntax error. You've spent 30 seconds initialising for nothing.

**Principle:** *Fail fast on cheap checks.* If the code doesn't even pass formatting, don't bother spinning up the rest of the pipeline.

**Diagnostic pathway:**
1. **What's missing?** Any check that the code is well-formed before init runs.
2. **What tools does Terraform give us for this?**
   - `terraform fmt -check` — verifies all `.tf` files match Terraform's canonical formatting style. Returns non-zero exit code if anything is misformatted.
   - `terraform validate` — checks the configuration for internal consistency: valid resource types, correct attribute names, references that resolve.
3. **What's the difference?** `fmt` is purely cosmetic (whitespace, alignment). `validate` is semantic (does this code actually make sense?). They catch different classes of error.
4. **Do we need both?** Yes, ideally. But there's an ordering subtlety: `fmt` doesn't need init (it operates on the source files alone), so it can run first. `validate` *does* need init (it needs to know about providers to fully validate). So the order becomes: **fmt → init → validate → plan → apply**.

**The fix:**

```yaml
    - name: Terraform Format Check
      run: terraform fmt -check -recursive

    - name: Terraform Init
      run: terraform init

    - name: Terraform Validate
      run: terraform validate
```

### Command breakdown — `terraform fmt -check -recursive`

| Component | What it does |
|---|---|
| `terraform fmt` | The formatter. Without flags, it rewrites files in place to match canonical style. |
| `-check` | Don't rewrite anything — just check, and exit non-zero if any file would be changed. This is what makes it fail the pipeline instead of silently fixing the code. |
| `-recursive` | Descend into subdirectories. Without this, only the current directory's `.tf` files are checked. |

### Command breakdown — `terraform validate`

| Component | What it does |
|---|---|
| `terraform validate` | Checks configuration validity against the loaded providers — confirms resource types exist, attributes are spelled correctly, references resolve, etc. |

No flags needed for the lab — defaults are fine. Note this **must run after init** because validate needs the provider plugins to know what resource types are valid.

---

## Step 6 — The complete fixed workflow

```yaml
# Terraform CI/CD Pipeline
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3

    - name: Terraform Format Check
      run: terraform fmt -check -recursive

    - name: Terraform Init
      run: terraform init

    - name: Terraform Validate
      run: terraform validate

    - name: Terraform Plan
      run: terraform plan

    - name: Terraform Apply
      if: github.event_name == 'push' && github.ref == 'refs/heads/main'
      run: terraform apply -auto-approve
```

Read it through and trace what happens in two scenarios:

**On a PR:** checkout → setup → fmt-check → init → validate → plan. Apply is skipped because the trigger is `pull_request`, not `push`. The reviewer sees the plan in the workflow log.

**On a merge to main:** checkout → setup → fmt-check → init → validate → plan → apply. All steps run because the trigger is `push` and the ref is `refs/heads/main`.

That's the full Terraform CI/CD pattern in one file.

---

## Step 7 — Validate

```bash
lab validate cicd/lab-045-terraform-iac-pipeline
```

You're looking for all four checks green:
- Pipeline includes terraform init ✅
- Pipeline includes terraform plan ✅
- Pipeline includes validation/formatting check ✅
- Apply is conditional (not running on PRs) ✅

---

## Things you should know about (but didn't fix in this lab)

These didn't appear as fixable items in the workflow file, but they're part of the complete picture and likely to come up in interviews.

### State locking

Terraform stores the state of your infrastructure (which resources exist, their IDs, their attributes) in a state file. If two pipeline runs apply at the same time, both writing to the same state file, the file gets corrupted — and recovering from a corrupted state file is genuinely awful.

The fix is **state locking**: before any operation, Terraform acquires a lock; only one operation can hold the lock at a time. With the S3 backend, locking is done via DynamoDB.

This isn't configured in the *workflow file* — it's configured in the Terraform code's backend block:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-locks"
  }
}
```

The workflow's job is to **not interfere** with locking — specifically, never use `-lock=false` in your apply commands. If a pipeline run hits a "state locked" error, the answer is to investigate the other run, not to disable locking.

### Posting plan output to the PR

The plan step we added writes its output to the workflow log. That works, but it's a poor review experience — the reviewer has to click through to GitHub Actions, find the right job, scroll the log. A better UX is to post the plan as a PR comment so it appears inline with the conversation.

The pattern is `terraform plan -no-color -out=tfplan` followed by an `actions/github-script` step that reads the plan output and calls the GitHub API to post it as a comment. The original solution sketched this — it's worth knowing about but is genuinely fiddly to get right (handling long output, multiple runs, etc.) and we've left it out to keep the lab focused.

### Saved plan files

In production, you don't run `plan` and `apply` as separate operations against live state — you run `plan -out=tfplan` to save the plan to a file, then `apply tfplan` to apply *exactly that saved plan*. Why? Because between plan and apply, the world could have changed (someone manually edited a resource in the AWS console). Applying the saved plan ensures what got reviewed is what gets applied. For this lab we've used the simpler form to keep the focus on pipeline structure.

---

## Real-World Extensions

- **Separate plan and apply jobs** with manual approval between them — the apply job waits for a human to click "approve" in the GitHub UI before running.
- **Environment promotion** — workflow deploys to dev, then staging, then production, with separate approval gates for each.
- **Drift detection** — a scheduled workflow runs `terraform plan` nightly. If the plan is non-empty (drift detected), it alerts the team.
- **Cost estimation** — tools like Infracost run as a step and post the cost impact of a PR's changes as a comment.
- **Policy as code** — OPA or Sentinel enforces rules ("no public S3 buckets", "all resources must be tagged") and blocks non-compliant plans before apply.

---

## Pi/K3s environment notes

This lab edits a static YAML file — it's filesystem-only. There's no Kubernetes, no Terraform execution, no AWS calls. Nothing about ARM64, K3s, or the Pi affects it. You can complete the lab on any machine with `git` and a text editor.

One caveat worth noting: `act` (the local GitHub Actions runner the challenge file mentions) **does not work reliably on ARM64**. If you wanted to actually run this workflow end-to-end you'd need to push it to GitHub and let GitHub Actions execute it on their x86 runners. For the purposes of this lab — which is about the *structure* of the workflow, not running it — that doesn't matter.

---

## Cleanup / Reset

To restore the lab to its broken state for another run:

```bash
git checkout -- .github/workflows/terraform.yml
```

That undoes all your changes to the workflow file, putting it back to the version with the bugs. No other state to clean up — there's nothing running, nothing deployed.

---

## Key concepts

- **`terraform init` must run before any other Terraform command** — it downloads providers, configures the backend, fetches modules. Without it, every subsequent command fails.
- **Plan on PR, apply on merge** — the fundamental Terraform CI/CD pattern. PRs are for review; merges are the signal that review is complete.
- **`if:` conditions on individual steps** control when steps run. The combination `github.event_name == 'push' && github.ref == 'refs/heads/main'` means "only on a real merge to main."
- **Fail fast on cheap checks** — `terraform fmt -check` is essentially free to run and catches problems before you pay for init's network calls.
- **`fmt` runs before `init`; `validate` runs after `init`** — because fmt operates on source files alone, but validate needs provider information.
- **State locking is a backend concern, not a workflow concern** — but the workflow must never disable it with `-lock=false`.

---

## Common mistakes

- **Forgetting `terraform init`** — the most common Terraform-in-CI mistake. Symptom: cryptic provider errors on the first real Terraform command.
- **Running apply on PRs** — applies untested, unreviewed changes. The condition `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` prevents this.
- **Putting `validate` before `init`** — validate needs the provider plugins that init downloads. It'll fail with "Missing required provider" or similar.
- **Using `-lock=false` to "fix" state lock errors** — disables the only thing protecting you from corrupted state. The right fix is to investigate why a lock is held (usually a previous run that died without releasing it) and clear it properly.
- **No formatting check** — code style drift accumulates fast across a team. Once the codebase is misformatted, getting it back is a painful PR. `terraform fmt -check` in CI prevents the drift from ever starting.
