# Solution Walkthrough — IAM Role Assumption Failed (Trust Policy Broken)

## The Problem

An application needs to assume a cross-account role to access shared services, but the `sts:AssumeRole` call is failing with "Access Denied." The role chain has **three bugs**:

1. **Trust policy references the wrong role ARN** — the target role's trust policy allows `arn:aws:iam::123456789012:role/wrong-role-name` instead of the actual application role ARN. Since the app role ARN doesn't match, STS rejects the assumption request.
2. **ExternalId condition creates a chicken-and-egg problem** — the trust policy requires an ExternalId (`required-external-id-12345`), but in this simple same-account scenario, ExternalId adds unnecessary complexity. For this lab, removing the condition simplifies the fix. (In real cross-account setups, ExternalId is a security best practice.)
3. **IAM policy uses wrong action** — the app role's policy grants `iam:PassRole` instead of `sts:AssumeRole`. These are completely different actions: `iam:PassRole` allows passing a role to an AWS service (like attaching a role to an EC2 instance), while `sts:AssumeRole` allows actually assuming the role to get temporary credentials.

## Thought Process

When role assumption fails, an experienced cloud engineer checks three things — the "role chain":

1. **Does the caller have permission to assume?** — the calling role needs an IAM policy with `sts:AssumeRole` for the target role's ARN.
2. **Does the target trust the caller?** — the target role's trust policy (assume role policy) must list the caller in its Principal.
3. **Do conditions match?** — if the trust policy has Conditions (like ExternalId), the caller must satisfy them.

All three must be correct for role assumption to work. A failure in any one produces "Access Denied."

## Step-by-Step Solution

### Step 1: Review the current configuration

```bash
terraform init
terraform plan
```

**What this does:** Shows the planned resources. Review each role and policy to trace the assumption chain.

### Step 2: Fix Bug 1 — Trust policy should reference the actual app role

The target role's trust policy has a hardcoded wrong ARN:

```hcl
# BROKEN: Trust policy references wrong role
Principal = {
  AWS = "arn:aws:iam::123456789012:role/wrong-role-name"
}
```

Fix it by referencing the actual app role using Terraform:

```hcl
Principal = {
  AWS = aws_iam_role.app_role.arn
}
```

**Why this matters:** The trust policy's Principal field defines WHO can assume this role. By using `aws_iam_role.app_role.arn`, Terraform automatically inserts the correct ARN. Hardcoding ARNs is fragile — role names or account IDs can change. Terraform resource references are always current.

### Step 3: Fix Bug 2 — Remove or satisfy the ExternalId condition

The trust policy requires an ExternalId:

```hcl
Condition = {
  StringEquals = {
    "sts:ExternalId" = "required-external-id-12345"
  }
}
```

For this lab, remove the Condition block entirely:

```hcl
# No Condition block — simplified for same-account assumption
```

**Why this matters:** ExternalId is a security mechanism for cross-account role assumption. It prevents the "confused deputy" problem — where a malicious third party tricks a service into assuming a role on their behalf. In a same-account scenario (which this lab simulates), ExternalId isn't needed. If you keep it, the calling code must include the matching ExternalId in the `sts:AssumeRole` API call.

### Step 4: Fix Bug 3 — Change iam:PassRole to sts:AssumeRole

The app role's policy grants the wrong action:

```hcl
# BROKEN: PassRole is not AssumeRole
Action = "iam:PassRole"
```

Fix it:

```hcl
Action = "sts:AssumeRole"
```

**Why this matters:** These are completely different IAM actions:
- **`sts:AssumeRole`** — allows the caller to assume a role and receive temporary credentials. This is what the application needs.
- **`iam:PassRole`** — allows the caller to pass a role to an AWS service (e.g., when launching an EC2 instance with an instance profile, or creating a Lambda function with an execution role). It doesn't grant the ability to assume the role yourself.

### Step 5: The complete fixed main.tf

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

### Step 6: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid. The plan should show three IAM resources with correct policies.

## Docker Lab vs Real Life

- **Cross-account in practice:** Real cross-account assumption involves two AWS accounts. Account A's role has a trust policy allowing Account B's role to assume it. Both the IAM policy in Account B AND the trust policy in Account A must be correct.
- **ExternalId is important in production:** When a third-party service (like Datadog or a partner company) needs to assume a role in your account, ExternalId prevents the "confused deputy" attack. The third party provides a unique ExternalId that only they know.
- **Session policies:** When assuming a role, you can pass a session policy that further restricts the assumed role's permissions. This is useful for granting temporary, scoped-down access.
- **Role chaining limits:** AWS limits role chaining to 1 hour session duration. If Role A assumes Role B, which assumes Role C, the maximum session duration for the final role is 1 hour (not the role's configured maximum).
- **AWS Organizations SCPs:** Service Control Policies can override role trust policies. Even if the trust policy allows assumption, an SCP can block it at the organization level.

## Key Concepts Learned

- **Role assumption requires three things** — (1) caller IAM policy with `sts:AssumeRole`, (2) target trust policy allowing the caller, (3) any conditions must be satisfied. All three must pass.
- **`sts:AssumeRole` and `iam:PassRole` are completely different** — AssumeRole gives you temporary credentials for a role. PassRole lets you assign a role to an AWS service. They serve different purposes and are not interchangeable.
- **Trust policies define WHO can assume a role** — the `assume_role_policy` on an IAM role is its trust policy. The Principal field lists the identities (users, roles, services, accounts) that are trusted.
- **Use Terraform references instead of hardcoded ARNs** — `aws_iam_role.app_role.arn` is always correct and updates automatically. Hardcoded ARNs break when names or account IDs change.
- **ExternalId prevents the confused deputy problem** — it's a shared secret between the caller and the trust policy. Without it, any entity in the trusted account could assume the role.

## Common Mistakes

- **Confusing trust policy with permissions policy** — the trust policy (`assume_role_policy`) defines who can ASSUME the role. The permissions policy defines what the role can DO once assumed. They're separate concepts.
- **Using `iam:PassRole` when `sts:AssumeRole` is needed** — PassRole is for delegating a role to a service (EC2, Lambda). AssumeRole is for getting temporary credentials yourself. This is the exact mistake in this lab.
- **Hardcoding ARNs in trust policies** — hardcoded ARNs are fragile. If the account ID or role name changes, the trust policy breaks silently. Use Terraform resource references wherever possible.
- **Forgetting the ExternalId in the API call** — if the trust policy requires an ExternalId and the caller doesn't provide it, assumption fails. The ExternalId must be passed in the `sts:AssumeRole` API call.
- **Not scoping the AssumeRole permission** — the IAM policy should specify which role(s) can be assumed in the Resource field. Using `Resource = "*"` allows assuming ANY role, which violates least privilege.
