# Lab 064 — Solution Walkthrough: IAM Role Assumption Failed (Trust Policy Broken)

---

## TLDR — Plain English Summary

Imagine you work at a large company with two departments. You work in Department A, and you need to borrow a temporary access badge from Department B to do some shared work. For this to work, three things need to be true:

1. **You need permission to request the badge** — someone in Department A must have authorised you to make badge requests.
2. **Department B must recognise who you are** — their register must list your name as someone allowed to borrow their badge.
3. **If there's a special passcode required, you need to know it** — and provide it correctly when you ask.

This lab has all three of those things broken:

- **Bug 1 (Wrong name on Department B's list):** The target role's trust policy says "let `wrong-role-name` borrow this badge" — but the app role asking is named something different entirely. AWS checks this list first and immediately says "you're not on here."
- **Bug 2 (A passcode is required but nobody told the app what it is):** The trust policy demands a special passcode called an `ExternalId`. Since this is a simple same-account setup, this passcode requirement adds unnecessary complication. We remove it. Note: there are two valid ways to fix this — remove the condition entirely (what we do here), or update the calling application to supply the correct ExternalId at runtime. In a real cross-account setup with a third party, you'd keep the ExternalId and make sure the caller supplies it.
- **Bug 3 (Wrong type of permission granted):** The app role was given permission to "hand a badge to a service" (`iam:PassRole`) instead of "borrow a badge yourself" (`sts:AssumeRole`). These are genuinely different things. Having `iam:PassRole` does nothing for role assumption. This bug won't fail at `terraform apply` — it only surfaces at runtime when the application actually tries to call STS and gets denied.

**The fix:** Correct the name on Department B's list to match the actual app role, remove the unnecessary passcode requirement, and replace `iam:PassRole` with `sts:AssumeRole` in the app role's policy.

---

## What is STS and What Does AssumeRole Actually Do?

**STS** stands for **Security Token Service** — a separate AWS service whose entire job is issuing temporary credentials.

When your application calls `sts:AssumeRole`, here is what actually happens:

1. Your app sends a request to STS: "I want to assume this role"
2. STS runs the three-way trust check (covered below)
3. If everything passes, STS hands back a **temporary access key, secret key, and session token**
4. Your app uses those credentials to make AWS API calls *as that role* for the duration of the session (typically up to 1 hour)
5. When they expire, the app calls `sts:AssumeRole` again to get fresh ones

The key word is **temporary**. You are not permanently becoming that role. You are borrowing a time-limited set of credentials — exactly like borrowing a badge that auto-expires.

This is why `sts:AssumeRole` and `iam:PassRole` are completely different:

| Action | What it actually does |
|--------|----------------------|
| `sts:AssumeRole` | You call STS, receive temporary credentials, and *you* act as the role |
| `iam:PassRole` | You hand a role to an AWS service (EC2, Lambda) for *it* to use — you receive no credentials yourself |

In plain English: `sts:AssumeRole` = **you borrow the badge yourself**. `iam:PassRole` = **you hand the badge to someone else to use**.

---

## The Role Assumption Mental Model — Read This First

Before touching any code, understand the three-way check that AWS performs every single time a role is assumed. All three must pass. A failure at any point returns a generic "Access Denied" with no indication of which check failed.

```
┌────────────────────────────────────────────────────────┐
│           THE THREE-WAY ROLE ASSUMPTION CHECK          │
├────────────────────────────────────────────────────────┤
│                                                        │
│  CHECK 1: Does the CALLER have permission?             │
│  → The calling role needs an IAM policy that           │
│    explicitly grants sts:AssumeRole for the            │
│    target role's ARN.                                  │
│                                                        │
│  CHECK 2: Does the TARGET ROLE trust the caller?       │
│  → The target role's trust policy (assume_role_policy) │
│    must list the caller in its Principal field.        │
│                                                        │
│  CHECK 3: Are all CONDITIONS satisfied?                │
│  → If the trust policy has Conditions (like            │
│    ExternalId), the caller must supply them            │
│    correctly in the API call.                          │
│                                                        │
│  All three ✅ = Temporary credentials issued by STS.   │
│  Any one ❌ = "Access Denied." (no further detail)     │
└────────────────────────────────────────────────────────┘
```

This is your diagnostic framework for every role assumption failure you will ever debug.

In this lab, Company A (`app_role`) is trying to assume Company B's role (`shared_services_role`). All three checks were broken. Each bug maps directly to one check failing.

---

## How to Read an IAM Policy Block — Work Backwards

IAM policy blocks are written in an order that doesn't match how you'd naturally think about access control. The way it's written — Effect → Action → Principal — puts the *outcome* before you even know who's involved or what they're trying to do.

**Read it in reverse instead:**

| Read order | Field | The question it answers |
|------------|-------|------------------------|
| 1st | **Action** | What is being attempted? (e.g. `sts:AssumeRole`) |
| 2nd | **Principal** | Who is attempting it? (e.g. `aws_iam_role.app_role.arn`) |
| 3rd | **Effect** | Are we allowing or denying it? (`Allow` / `Deny`) |

This maps directly to how a real authorisation decision flows — and how you'd naturally debug one: *what failed? → who was doing it? → were they supposed to be allowed to?*

**One important caveat:** `Principal` only appears in **trust policies** (the `assume_role_policy` on a role). In a regular permissions policy, the "who" is implicit — it's whoever the policy is attached to. But the Action → Effect reading direction still holds for everything else.

---

## Step-by-Step Investigation & Fix

### Step 1 — Initialise Terraform and read the plan

```bash
terraform init
```

| Component | What it does |
|-----------|-------------|
| `terraform` | The Terraform CLI tool |
| `init` | Initialises the working directory — downloads required providers (in this case `hashicorp/aws`), sets up the backend, and prepares Terraform to run plans and applies |

```bash
terraform plan
```

| Component | What it does |
|-----------|-------------|
| `terraform` | The Terraform CLI tool |
| `plan` | Reads your `.tf` files and shows what resources would be created, changed, or destroyed — without making any real changes. This is your read-only inspection step |

**What you're looking for:** Read through the plan output carefully. You're looking at three IAM resources. Your goal is to trace the role assumption chain: who is the caller, who is the target, what does the target's trust policy say, and what permissions does the caller have?

**Important:** `terraform plan` will succeed even with broken IAM policies. Terraform cannot validate principal ARNs or policy logic at plan time — it only checks HCL syntax. AWS validates the actual policy content at apply time and will reject it there. A clean plan does not guarantee a clean apply.

---

### Step 2 — Investigate and fix Bug 1: Wrong ARN in the trust policy

**How to spot it:**

Look at `aws_iam_role.shared_services_role` in `main.tf`. Find the `assume_role_policy` block — this is Company B's trust policy, the guestlist. The Principal field will show:

```json
"Principal": {
  "AWS": "arn:aws:iam::123456789012:role/wrong-role-name"
}
```

Ask yourself: is `wrong-role-name` the same role defined as `aws_iam_role.app_role` in this config? No — the names don't match, and `123456789012` is an AWS documentation placeholder account ID, not your real account.

**Why this matters:**

When the app role tries to assume `shared_services_role`, AWS checks: "Is this caller's ARN on the guestlist?" The answer is no — the guestlist has a completely different name on it. AWS returns "Access Denied" immediately, before even checking the other two things. You will also see this fail at `terraform apply` itself — AWS rejects the trust policy at role creation time because the principal ARN references a fake account.

**The fix:**

```hcl
# BEFORE
Principal = {
  AWS = "arn:aws:iam::123456789012:role/wrong-role-name"
}

# AFTER
Principal = {
  AWS = aws_iam_role.app_role.arn
}
```

| Before | After | Why |
|--------|-------|-----|
| Hardcoded wrong ARN | `aws_iam_role.app_role.arn` | A Terraform resource reference resolves to the exact ARN of the role defined in this config, using your real account ID. It's always correct and updates automatically if the role name ever changes. |

When Terraform applies this, you'll see it resolve in the plan to something like `arn:aws:iam::340752829546:role/app-role` — your real account ID and the correct role name.

---

### Step 3 — Investigate and fix Bug 2: The ExternalId condition

**How to spot it:**

Still in the trust policy for `shared_services_role`, look for a `Condition` block:

```hcl
Condition = {
  StringEquals = {
    "sts:ExternalId" = "required-external-id-12345"
  }
}
```

Ask yourself: is anything in this configuration supplying this ExternalId when calling `sts:AssumeRole`? No. The trust policy is demanding a passcode that nobody is providing.

**Two ways to fix this:**

---

**Option 1 — Remove the condition (what we do in this lab):**

If ExternalId isn't needed for the scenario — a same-account setup like this lab — remove the Condition block entirely.

```hcl
# BEFORE — trust policy requires an ExternalId that nobody is supplying
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = {
      AWS = aws_iam_role.app_role.arn
    }
    Action    = "sts:AssumeRole"
    Condition = {
      StringEquals = {
        "sts:ExternalId" = "required-external-id-12345"
      }
    }
  }]
})

# AFTER — condition removed, no passcode required
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = {
      AWS = aws_iam_role.app_role.arn
    }
    Action = "sts:AssumeRole"
  }]
})
```

---

**Option 2 — Keep the condition and satisfy it at runtime (production cross-account pattern):**

In a real cross-account setup with a third party, you'd keep the ExternalId in the trust policy — that's the security control. The fix is on the **calling application side**, not in Terraform. The application must pass the matching ExternalId in its `sts:AssumeRole` API call.

The trust policy stays as-is (or uses a real agreed ExternalId rather than the placeholder):

```hcl
# Trust policy — ExternalId kept, but using a real agreed value
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"
    Principal = {
      AWS = aws_iam_role.app_role.arn
    }
    Action    = "sts:AssumeRole"
    Condition = {
      StringEquals = {
        "sts:ExternalId" = "required-external-id-12345"
      }
    }
  }]
})
```

And the calling application must include the ExternalId in the API call. In Python (boto3) that looks like:

```python
# BEFORE — no ExternalId passed, trust policy rejects the call
sts_client = boto3.client('sts')
response = sts_client.assume_role(
    RoleArn="arn:aws:iam::123456789012:role/shared-services-role",
    RoleSessionName="app-session"
)

# AFTER — ExternalId included, trust policy condition is satisfied
sts_client = boto3.client('sts')
response = sts_client.assume_role(
    RoleArn="arn:aws:iam::123456789012:role/shared-services-role",
    RoleSessionName="app-session",
    ExternalId="required-external-id-12345"   # must match the trust policy exactly
)
```

The ExternalId is not configured anywhere in IAM on the caller's side — it's passed as a runtime argument in the API call itself. If the strings don't match exactly, STS rejects the request even if the Principal and Action are both correct.

---

**What ExternalId protects against:**

ExternalId prevents the "confused deputy" problem. Imagine Datadog is trusted to assume roles in your account. A malicious actor could trick Datadog into assuming your role on their behalf — because Datadog is trusted, and the trust policy doesn't know who's actually driving the request. An ExternalId is a shared secret only you and Datadog know. The malicious actor doesn't have it, so their requests fail.

**For this lab — use Option 1. Remove the Condition block entirely.**

---

### Step 4 — Investigate and fix Bug 3: Wrong IAM action

**How to spot it:**

Look at `aws_iam_role_policy.assume_role_policy` — the permissions policy attached to the app role. Find the `Action` field:

```hcl
Action = "iam:PassRole"
```

Ask yourself: the app role needs to *call `sts:AssumeRole`* on the shared services role. Does having `iam:PassRole` permission enable that? No.

**Why this matters:**

`iam:PassRole` and `sts:AssumeRole` are completely different mechanisms. PassRole is for delegating a role to an AWS service — for example, when you create a Lambda function and tell it which execution role to use, you need `iam:PassRole`. You don't receive any credentials yourself. It has nothing to do with assuming a role.

This bug is particularly sneaky because it **does not fail at `terraform apply`**. AWS will happily create an IAM policy with `iam:PassRole` — the policy itself is valid HCL and valid IAM. The failure only surfaces at runtime when the application actually tries to call STS and AWS checks whether it has `sts:AssumeRole` permission. It doesn't. Access denied.

**The fix:**

```hcl
# BEFORE
Action = "iam:PassRole"

# AFTER
Action = "sts:AssumeRole"
```

---

### Step 5 — The complete fixed main.tf

```hcl
resource "aws_iam_role" "app_role" {
  name = "app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "shared_services_role" {
  name = "shared-services-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        AWS = aws_iam_role.app_role.arn
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "assume_role_policy" {
  name = "assume-shared-services"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.shared_services_role.arn
    }]
  })
}
```

**Line-by-line breakdown — `aws_iam_role.app_role` (Company A — the caller):**

| Line | What it does |
|------|-------------|
| `name = "app-role"` | The name of the role as it appears in AWS IAM and in ARNs |
| `assume_role_policy = jsonencode({...})` | The trust policy — who is allowed to assume this role. `jsonencode()` converts HCL to the JSON string AWS requires |
| `Principal = { Service = "ec2.amazonaws.com" }` | Trusts the EC2 service to assume this role. In a real deployment this role would be attached to an EC2 instance as an instance profile. In this lab your Pi is the equivalent of that EC2 instance. |
| `Action = "sts:AssumeRole"` | The action being permitted in the trust policy — this is always `sts:AssumeRole` in a trust policy |

**Line-by-line breakdown — `aws_iam_role.shared_services_role` (Company B — the target):**

| Line | What it does |
|------|-------------|
| `name = "shared-services-role"` | The name as it appears in AWS IAM and in ARNs |
| `assume_role_policy = jsonencode({...})` | Company B's trust policy — the guestlist defining who can assume this role |
| `Principal = { AWS = aws_iam_role.app_role.arn }` | Trusts the app role specifically. `AWS` means an IAM principal (user, role, or account). This Terraform reference resolves to the real ARN at apply time. |
| `Action = "sts:AssumeRole"` | Always the action in a trust policy — the only thing a trust policy ever permits is being assumed |

**Line-by-line breakdown — `aws_iam_role_policy.assume_role_policy` (Company A's permission to knock on the door):**

| Line | What it does |
|------|-------------|
| `resource "aws_iam_role_policy"` | An inline policy — attached directly to a specific role rather than being a standalone managed policy |
| `role = aws_iam_role.app_role.id` | Attaches this policy to the app role. `.id` returns the role name, which is what this resource type expects |
| `Action = "sts:AssumeRole"` | Grants the app role the right to call AssumeRole — the caller-side permission (Check 1 in the three-way model) |
| `Resource = aws_iam_role.shared_services_role.arn` | Scopes the permission to this specific role only. Never use `"*"` here — that would allow assuming any role in the account, violating least privilege. |

---

### Step 6 — Validate and confirm

```bash
terraform validate
```

| Component | What it does |
|-----------|-------------|
| `terraform` | The Terraform CLI |
| `validate` | Checks syntax and internal consistency of your `.tf` files. Catches missing arguments, wrong types, or references to non-existent resources. Does not make API calls to AWS. |

```bash
terraform apply -auto-approve
```

| Component | What it does |
|-----------|-------------|
| `terraform` | The Terraform CLI |
| `apply` | Creates or updates resources in AWS to match the configuration |
| `-auto-approve` | Skips the manual yes/no confirmation prompt |

A clean apply with all three resources created and no errors confirms all three bugs are resolved.

---

## The Diagnostic Playbook — Role Assumption Failures in Real Life

When you hit "Access Denied" on `sts:AssumeRole` in production, work through this checklist in order:

**1. Confirm who is calling.** What's the ARN of the caller? Check CloudTrail if you're not sure. You need the exact ARN — account ID, role name, everything.

**2. Check the caller's permissions (Check 1).** Does the calling role's policy include `sts:AssumeRole` with a `Resource` that matches the target role's ARN? Critically — is the action actually `sts:AssumeRole` and not `iam:PassRole`?

**3. Check the target's trust policy (Check 2).** Go to IAM → Roles → [target role] → Trust relationships. Is the caller's exact ARN in the Principal field? Account IDs matter. Role names are case-sensitive.

**4. Check conditions (Check 3).** Is there an ExternalId condition? An IP condition? A `aws:PrincipalOrgID` condition? Does the calling context satisfy all of them?

**5. Check for SCPs.** If the account is in an AWS Organization, a Service Control Policy can block `sts:AssumeRole` even if everything else looks correct.

**6. Check for permission boundaries.** A permissions boundary on the calling role can prevent `sts:AssumeRole` even if the attached policy allows it.

---

## Real-World Context

**Cross-account role assumption** is how large organisations share services without sharing credentials. Account A (your app) assumes a role in Account B (shared services). Both the trust policy in Account B AND the IAM policy in Account A must be correct. The bugs in this lab are the exact bugs that appear in real cross-account setups.

**EC2 and instance profiles** — the `app_role` trust policy trusts `ec2.amazonaws.com`. In a real deployment this role would be attached to an EC2 instance as an instance profile. The EC2 service calls `sts:AssumeRole` on behalf of the instance, STS issues temporary credentials, and any application running on that instance can make AWS API calls without hardcoded keys. Your Pi is playing the role of that EC2 instance in this lab.

**ExternalId in production** — when a third party (Datadog, Splunk, a partner) needs to assume a role in your account, you agree an ExternalId out of band. They include it in every `sts:AssumeRole` call. Without it, any customer of that third party could potentially exploit the trust relationship to access your account.

**Least privilege on AssumeRole** — always scope the `Resource` in `sts:AssumeRole` policies to specific role ARNs. `Resource: "*"` allows assuming any role in the account, including admin roles.

**Role chaining** — if Role A assumes Role B which assumes Role C, the maximum session duration is 1 hour regardless of what any individual role is configured for. This matters for long-running batch jobs.

**Session duration** — `max_session_duration = 3600` (visible in the Terraform plan output) means temporary credentials from this role last a maximum of 1 hour. The application must refresh them before expiry.

---

## Key Concepts Summary

| Concept | What to remember |
|---------|-----------------|
| STS | Security Token Service — the AWS service that issues temporary credentials when `sts:AssumeRole` is called |
| Trust policy vs permissions policy | Trust policy = who can ASSUME the role. Permissions policy = what the role can DO once assumed. Two completely separate things. |
| `sts:AssumeRole` | You call STS, receive temporary credentials, and act as the role yourself |
| `iam:PassRole` | You hand a role to an AWS service for it to use. You receive no credentials. Completely different from AssumeRole. |
| Reading IAM blocks | Read Action → Principal → Effect (backwards from how it's written) — what's being attempted, who's doing it, are they allowed |
| Terraform resource references | `aws_iam_role.app_role.arn` always resolves correctly. Hardcoded ARNs break silently when names or account IDs change. |
| ExternalId | A shared secret for cross-account assumption. Prevents the confused deputy problem. Not needed for same-account scenarios. |
| "Access Denied" on AssumeRole | Check all three: caller policy, target trust policy, conditions. All three must pass. |

---

## Common Mistakes to Avoid

**Confusing trust policy with permissions policy.** Trust policy = the `assume_role_policy` on the target role, defines who can assume it. Permissions policy = attached to the caller, defines what it can do. They're in different places in the console and answer completely different questions.

**Using `iam:PassRole` when `sts:AssumeRole` is needed.** PassRole is for handing a role to a service. AssumeRole is for getting temporary credentials yourself. This bug will not fail at `terraform apply` — it only surfaces at runtime.

**Hardcoding ARNs in trust policies.** If the account ID or role name changes, the trust policy breaks silently. Use Terraform references.

**Not scoping AssumeRole permissions.** `Resource: "*"` on an AssumeRole policy violates least privilege and is a significant security risk in production.

**Assuming a clean plan means a clean apply.** Terraform validates HCL syntax at plan time, but AWS validates policy content (including principal ARNs) at apply time. Always apply and verify.

---

## Pi/K3s Lab Notes

This lab runs against real AWS IAM — there are no Pi-specific environment constraints. Terraform communicates directly with AWS APIs from the Pi using the credentials configured via `aws configure`. All behaviour observed is identical to running this lab from any other machine.

---

## Cleanup & Reset — Run Again From Step 1

Two things need to happen to fully reset this lab: AWS resources destroyed, and `main.tf` restored to its broken state.

**Step 1 — Destroy the AWS resources:**

```bash
terraform destroy -auto-approve
```

| Component | What it does |
|-----------|-------------|
| `terraform` | The Terraform CLI |
| `destroy` | Destroys all resources tracked in the current Terraform state — in this lab, the two IAM roles and the inline policy |
| `-auto-approve` | Skips the manual yes/no confirmation prompt |

**Step 2 — Restore the broken `main.tf` from the repo:**

```bash
git checkout main.tf
```

| Component | What it does |
|-----------|-------------|
| `git` | The Git CLI |
| `checkout` | In this context (with a filename rather than a branch name), discards all uncommitted local changes to the specified file and restores it to the last committed version from the repo |
| `main.tf` | The specific file to restore — your fixed version is discarded, the broken version from GitHub is restored |

**Why this works:** The broken state is committed in the GitHub repo. Your fixes were only ever made locally on the Pi and never pushed. `git checkout main.tf` throws away the local changes and pulls the file back from the repo — which still holds the three bugs exactly as they were.

**Verify the reset worked:**

```bash
cat main.tf
```

You should see `wrong-role-name`, the `ExternalId` condition, and `iam:PassRole` all back in place. If you do — the lab is fully reset and ready to run from Step 1.
