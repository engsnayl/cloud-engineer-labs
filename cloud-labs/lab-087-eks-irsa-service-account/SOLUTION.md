# Lab 087 — Solution Walkthrough: EKS Pod Can't Access AWS (IRSA Misconfigured)

---

## ⚠️ DESTROY REMINDER — TOP OF FILE ⚠️

This lab provisions real EKS + NAT Gateway infrastructure. **Run `./destroy.sh` when finished.** Cost if forgotten overnight: ~£4-5. Cost over a weekend: ~£10+. There is another destroy reminder at the bottom of this file — you will be reminded again.

---

## TLDR — Plain English

**The problem:** A pod in Kubernetes needs to reach AWS services (S3 and DynamoDB). The mechanism that lets it do that is called **IRSA** — IAM Roles for Service Accounts. Think of IRSA as a trust handshake between Kubernetes and AWS: the pod gets a temporary ID card from Kubernetes, and AWS is configured to accept that ID card and swap it for real AWS credentials.

In this lab, that handshake is broken in **six places**. Three are on the AWS side (in Terraform), two are on the Kubernetes side (in YAML files), and one is a security problem (the IAM permissions are too wide open).

**The fix, in plain terms:**
1. AWS expects the ID card to be labelled for a service called `sts.amazonaws.com`. The code labels it for `ec2.amazonaws.com`. Fix the label.
2. AWS needs to know *which* Kubernetes cluster's ID cards to trust. The code uses a placeholder instead of the real cluster address. Use the real address.
3. The pod's permissions currently say "do anything to anything". Tighten them to "do these specific things to this one bucket and this one table".
4. The Kubernetes ServiceAccount has the wrong sticker on it — it's using an old-style sticker from a deprecated tool. Use the new-style sticker AWS actually looks for.
5. The pod is using the default ServiceAccount instead of the one we configured. Point it at the right one.

**How you'll know it's fixed:** The pod's logs will show it successfully listing the S3 bucket and reading the DynamoDB item, instead of "Unable to locate credentials".

---

## The Ticket You've Been Handed

```
INCIDENT-EKS-001

Application pod logs showing "Unable to locate credentials" and
"AccessDeniedException" when calling S3 and DynamoDB.

IRSA was configured last sprint but never tested properly.

Get the pod working. Security team wants the IAM policy tightened
before they sign off.
```

No other context. You've got the Terraform repo in front of you. Now what?

---

## Step 1 — Deploy what you were given and reproduce the failure

**Why:** Before you touch anything, reproduce the reported problem. If you start editing code without seeing the failure yourself, you're guessing. You also want to know what *kind* of failure it is — does `terraform apply` even succeed? Does the pod start? Does it start and then fail at runtime?

```bash
cd cloud-engineer-labs/labs/lab-087-eks-irsa-misconfigured
terraform init
terraform apply
```

**What happens:** `terraform apply` runs for ~15 minutes (EKS clusters are slow to provision) and **succeeds**. Everything green. No errors.

So the infrastructure layer is fine. The failure must be at the runtime layer — the pod actually trying to use the credentials.

### Command breakdown

| Command | What each part does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin and the VPC module. Reads `main.tf` and pulls whatever it needs into `.terraform/`. You do this once per clone. |
| `terraform apply` | Reads all `.tf` files, asks AWS for the current state, calculates the difference, shows you a plan, then prompts `yes` to proceed. Creates the VPC, EKS cluster, node group, OIDC provider, IAM role, IAM policy, S3 bucket, DynamoDB table. |

---

## Step 2 — Wire up kubectl to the new cluster

**Why:** You now have an EKS cluster but your `kubectl` doesn't know about it. You need to tell `kubectl` how to talk to it by updating your kubeconfig file.

**Ask yourself:** *Where do I get the cluster name from?* It's an output of the Terraform run. You don't need to hardcode anything — let the code tell you.

```bash
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region)
kubectl get nodes
```

You should see one node in `Ready` state.

### Command breakdown

| Command | What each part does |
|---|---|
| `aws eks update-kubeconfig` | AWS CLI command that appends a new context to your `~/.kube/config` file |
| `--name <cluster-name>` | Which EKS cluster to configure. |
| `--region <region>` | Which AWS region the cluster is in. Without this, AWS CLI uses your default region, which may not match where the cluster lives. |
| `$(terraform output -raw cluster_name)` | Shell substitution — runs the inner command and pastes its output into the outer command. `-raw` strips quotes so the output is usable directly. |
| `kubectl get nodes` | Confirms kubectl can reach the cluster. If this fails, nothing else will work. |

---

## Step 3 — Apply the Kubernetes manifests with the right values

**Why:** The YAML files in `manifests/` have placeholders (`REPLACE_WITH_ROLE_ARN`, `REPLACE_WITH_BUCKET_NAME`). You need to substitute the real values before applying — those values come from Terraform outputs.

```bash
ROLE_ARN=$(terraform output -raw app_role_arn)
BUCKET=$(terraform output -raw s3_bucket_name)
TABLE=$(terraform output -raw dynamodb_table_name)

sed -i "s|REPLACE_WITH_ROLE_ARN|$ROLE_ARN|" manifests/serviceaccount.yaml
sed -i "s|REPLACE_WITH_BUCKET_NAME|$BUCKET|" manifests/pod.yaml
sed -i "s|REPLACE_WITH_TABLE_NAME|$TABLE|" manifests/pod.yaml

kubectl apply -f manifests/
```

### Command breakdown

| Command | What each part does |
|---|---|
| `sed -i "s|find|replace|" file` | In-place string substitution. `-i` means edit the file directly rather than printing to stdout. `\|` is the delimiter (used instead of `/` because the replacement contains forward slashes in the ARN). |
| `kubectl apply -f manifests/` | Apply every YAML file in the `manifests/` directory. Creates the ServiceAccount and the Pod. |

---

## Step 4 — Watch the pod fail

**Why:** This is the moment of truth — seeing the actual failure mode with your own eyes, not what someone else reported in the ticket.

```bash
kubectl logs app-pod -n default --tail=20
```

You should see something like:

```
=== Tue Oct 15 13:42:01 UTC 2026 ===
--- Testing S3 ---
Unable to locate credentials. You can configure credentials by running "aws configure".
S3 call failed
--- Testing DynamoDB ---
Unable to locate credentials. You can configure credentials by running "aws configure".
DynamoDB call failed
```

**What this tells you:**

- The pod is running. It's not crashing, it's not stuck pulling an image, it's not OOMKilled. It's just… calling AWS and getting told it has no credentials.
- "Unable to locate credentials" specifically means the AWS SDK (used by `aws s3 ls` under the hood) looked in all the usual places for credentials and found none.

### The places the AWS SDK looks for credentials, in order:

1. Environment variables (`AWS_ACCESS_KEY_ID`, etc.)
2. Shared credentials file (`~/.aws/credentials`)
3. **Web Identity Token File** (the IRSA mechanism) — set via `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` env vars
4. EC2 Instance Metadata Service

For IRSA to work, step 3 must be in play. The pod must have the `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` environment variables automatically injected by EKS. **If it doesn't, you know the Kubernetes side of the chain isn't even getting recognised as an IRSA pod.**

Let's check:

```bash
kubectl exec app-pod -n default -- env | grep -i aws
```

**Expected output if IRSA is wired up:**
```
AWS_REGION=eu-west-2
AWS_DEFAULT_REGION=eu-west-2
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/eks-app-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

**Actual output:**
```
AWS_REGION=eu-west-2
```

Nothing. No `AWS_ROLE_ARN`, no token file. **EKS has not recognised this pod as an IRSA pod at all.**

### Command breakdown

| Command | What each part does |
|---|---|
| `kubectl logs app-pod` | Streams the container's stdout/stderr. |
| `--tail=20` | Show only the last 20 lines. |
| `kubectl exec app-pod -- env` | Run `env` inside the container and print output. The `--` separates `kubectl` arguments from the command to run in the container. |
| `\| grep -i aws` | Filter to lines containing "aws", case-insensitive. |

---

## Step 5 — Why isn't EKS injecting the IRSA environment variables?

**Ask yourself:** *EKS injects those env vars only when the pod's ServiceAccount has a specific annotation. Does it?*

```bash
kubectl get serviceaccount app-service-account -n default -o yaml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: default
  annotations:
    iam.amazonaws.com/role: arn:aws:iam::ACCOUNT:role/eks-app-role
```

**What you're looking at:** The annotation is there. But the *key* is wrong.

**How would you know that?** Because EKS/IRSA looks for a specific annotation key: `eks.amazonaws.com/role-arn`. The annotation here is `iam.amazonaws.com/role` — that's a different annotation used by **kube2iam**, an older community project that predates IRSA. Somebody copied an old Stack Overflow answer.

**Quick sanity check:** Search the AWS IRSA docs for the exact annotation key — it's `eks.amazonaws.com/role-arn`. Mismatched annotation = EKS never recognises the pod as an IRSA pod = no env vars injected = `Unable to locate credentials`.

**That's bug #1 found. But there's also bug #2 in the same area — is the pod even using this ServiceAccount?**

```bash
kubectl get pod app-pod -n default -o jsonpath='{.spec.serviceAccountName}'
```

Output: `default`

**Huh.** The pod is using the `default` ServiceAccount, not `app-service-account`. Even if the annotation were correct, the pod wouldn't pick it up — it's attached to the wrong ServiceAccount.

**Fix both Kubernetes bugs now.**

Edit `manifests/serviceaccount.yaml`:

```yaml
# Before
annotations:
  iam.amazonaws.com/role: arn:aws:iam::ACCOUNT:role/eks-app-role

# After
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/eks-app-role
```

Edit `manifests/pod.yaml`:

```yaml
# Before
spec:
  serviceAccountName: default

# After
spec:
  serviceAccountName: app-service-account
```

Reapply and recreate the pod (pods don't pick up ServiceAccount changes until recreated):

```bash
kubectl apply -f manifests/
kubectl delete pod app-pod -n default
kubectl apply -f manifests/pod.yaml
```

Then check again:

```bash
kubectl exec app-pod -n default -- env | grep -i aws
```

**Now you should see:**
```
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/eks-app-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

EKS is now recognising the pod as an IRSA pod. Progress.

### Command breakdown

| Command | What each part does |
|---|---|
| `kubectl get serviceaccount ... -o yaml` | Fetch the ServiceAccount and print it as YAML. Useful for spotting exact annotation keys. |
| `-o jsonpath='{.spec.serviceAccountName}'` | Output only the `serviceAccountName` field using a JSONPath query. Better than piping `grep` when you want an exact field. |
| `kubectl delete pod ... && kubectl apply -f ...` | Pods are mostly immutable — you can't change `serviceAccountName` on a running pod. Delete and recreate. |

---

## Step 6 — Check the logs again

```bash
kubectl logs app-pod -n default --tail=20
```

```
--- Testing S3 ---
An error occurred (WebIdentityErr) when calling the AssumeRoleWithWebIdentity
operation: Not authorized to perform sts:AssumeRoleWithWebIdentity
S3 call failed
```

**Different error.** Progress — the pod is now trying to assume the IAM role, but AWS is refusing.

**What does this error mean?** The pod has successfully found an IAM role to try to assume (good — IRSA env vars worked). But the IAM role's **trust policy** — the thing that says *"I will allow these principals to assume me"* — is rejecting the pod.

Trust policies have conditions. When the pod tries to assume the role, AWS checks:
- Does the federated principal match?
- Do the condition keys match?

If any condition fails, you get `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

---

## Step 7 — Inspect the IAM role's trust policy

```bash
aws iam get-role --role-name eks-app-role --query 'Role.AssumeRolePolicyDocument' --output json
```

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/ABC123..."
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks:sub": "system:serviceaccount:default:app-service-account",
          "oidc.eks:aud": "ec2.amazonaws.com"
        }
      }
    }
  ]
}
```

**Three things look wrong here. Work through them one by one.**

### Problem A: The condition key prefix is wrong

`"oidc.eks:sub"` and `"oidc.eks:aud"` are literally the strings `oidc.eks:sub` and `oidc.eks:aud`. That's not how IRSA works.

**How does IRSA actually work?** The JWT token the pod presents contains claims — `sub` (subject = which K8s service account) and `aud` (audience = who this token is for). AWS evaluates these claims using condition keys that are **prefixed with the OIDC issuer URL** of the specific cluster. So the correct key format is:

```
oidc.eks.eu-west-2.amazonaws.com/id/ABC123...:sub
oidc.eks.eu-west-2.amazonaws.com/id/ABC123...:aud
```

The full issuer URL (minus the `https://`), then `:sub` or `:aud`.

**Where do I get the real OIDC issuer URL from?**

```bash
terraform output oidc_issuer
```

Or directly from AWS:

```bash
aws eks describe-cluster --name lab-087-cluster --query 'cluster.identity.oidc.issuer' --output text
```

In Terraform, you reference it as `aws_eks_cluster.main.identity[0].oidc[0].issuer`. There's already a local in `main.tf` doing this correctly — `local.oidc_issuer_stripped` strips the `https://` prefix. It's just not being used in the trust policy. Use it.

### Problem B: The aud condition value is wrong

`"oidc.eks:aud" = "ec2.amazonaws.com"` — the `aud` (audience) claim in IRSA JWT tokens is always `sts.amazonaws.com`, because STS is the service the token is being presented to. Not EC2.

### Problem C: There's a related bug in the OIDC provider itself

Look at the `aws_iam_openid_connect_provider` resource:

```hcl
client_id_list = ["ec2.amazonaws.com"]
```

The `client_id_list` is the list of audiences AWS will accept in JWT tokens for this OIDC provider. If it's `ec2.amazonaws.com`, AWS will only accept tokens intended for EC2 — but IRSA tokens are intended for `sts.amazonaws.com`. This is the root cause of why `aud` conditions are wrong everywhere.

### Fix all three in `main.tf`:

```hcl
# OIDC provider
resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

# Trust policy
Condition = {
  StringEquals = {
    "${local.oidc_issuer_stripped}:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
    "${local.oidc_issuer_stripped}:aud" = "sts.amazonaws.com"
  }
}
```

Apply:

```bash
terraform apply
```

### Command breakdown

| Command | What each part does |
|---|---|
| `aws iam get-role --role-name <name>` | Fetch the IAM role definition from AWS. |
| `--query 'Role.AssumeRolePolicyDocument'` | JMESPath filter — return only the trust policy, not the full role metadata. |
| `--output json` | Pretty-print as JSON (default is a less-readable format). |
| `aws eks describe-cluster` | Fetch cluster metadata. OIDC issuer URL lives under `cluster.identity.oidc.issuer`. |

---

## Step 8 — Verify the pod works

After `terraform apply` completes, give it 30 seconds for the IAM changes to propagate (IAM is eventually consistent — this matters in real life and comes up in interviews), then:

```bash
kubectl delete pod app-pod -n default
kubectl apply -f manifests/pod.yaml
kubectl logs -f app-pod -n default
```

```
=== Tue Oct 15 13:55:12 UTC 2026 ===
--- Testing S3 ---
2026-10-15 13:55:12          0 test-object.txt
--- Testing DynamoDB ---
{
    "Item": {
        "value": {
            "S": "hello from irsa lab"
        },
        "id": {
            "S": "test-id"
        }
    }
}
```

The pod is now successfully calling AWS. **The functional bugs are fixed.**

---

## Step 9 — The security finding (bug #6)

Reread the ticket:

> Security team wants the IAM policy tightened before they sign off.

Look at `aws_iam_role_policy.app_permissions` in `main.tf`:

```hcl
{
  Effect = "Allow"
  Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
  Resource = "*"
},
{
  Effect = "Allow"
  Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
  Resource = "*"
}
```

**`Resource = "*"` means this role can read/write every S3 bucket and every DynamoDB table in the AWS account.** If this pod is ever compromised (a supply chain attack, a code injection vulnerability, an exposed secret), an attacker gets a foothold across every bucket in the account. That's a pass-the-hash of cloud access.

**Fix: scope each statement to the specific resources the pod actually needs.**

```hcl
{
  Effect = "Allow"
  Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
  Resource = [
    aws_s3_bucket.app_data.arn,
    "${aws_s3_bucket.app_data.arn}/*"
  ]
},
{
  Effect = "Allow"
  Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
  Resource = aws_dynamodb_table.app_state.arn
}
```

**Why two ARNs for S3?** Because the bucket itself (`arn:aws:s3:::bucket-name`) is a distinct resource from the objects inside it (`arn:aws:s3:::bucket-name/*`). `s3:ListBucket` acts on the bucket, `s3:GetObject` and `s3:PutObject` act on objects. You need both.

Apply:

```bash
terraform apply
```

---

## Step 10 — Validate

```bash
./validate.sh
```

All checks should pass. If any fail, read the check name and go back to the relevant step.

---

## Step 11 — 🚨 TEAR DOWN THE INFRASTRUCTURE 🚨

**Do this now, before you do anything else.**

```bash
./destroy.sh
```

The script deletes K8s resources, empties the S3 bucket, runs `terraform destroy`, then verifies no EKS clusters, NAT Gateways, or OIDC providers remain.

If the destroy fails partway through, **do not ignore it**. Common causes:
- S3 bucket not empty → run `aws s3 rm s3://<bucket> --recursive` manually
- IAM eventual consistency → wait 30 seconds and rerun
- Kubernetes finalizers hanging → `kubectl delete pod app-pod --force`

After the script succeeds, sanity-check with the AWS console or:

```bash
aws eks list-clusters --region eu-west-2
aws ec2 describe-nat-gateways --region eu-west-2 --filter "Name=state,Values=available,pending"
```

Both should return empty.

---

## Key Concepts Learned

**IRSA is a three-layer chain, and any broken link breaks the whole thing:**

1. **AWS OIDC provider** — AWS is told "I will accept JWT tokens signed by this cluster's OIDC issuer, with audience `sts.amazonaws.com`."
2. **IAM role trust policy** — the role says "I will let you assume me if your JWT's `sub` claim matches this specific ServiceAccount AND your `aud` claim is `sts.amazonaws.com`."
3. **Kubernetes ServiceAccount** — annotated with `eks.amazonaws.com/role-arn` so EKS injects the right env vars into pods that use it. Pod must reference the ServiceAccount by name.

**Least privilege applies to workload IAM too.** Pod roles with `Resource = "*"` are a recurring audit finding in real shops. The cost of fixing it is five minutes; the cost of not fixing it can be catastrophic.

**IAM is eventually consistent.** Trust policy changes, role policy changes — all of these can take 10-30 seconds to propagate. If a fix seems not to work, wait and retry before assuming you got it wrong.

---

## Lab vs Real Life

| Lab | Real Life |
|---|---|
| One pod, one bucket, one table | Dozens of pods across multiple namespaces, each needing their own scoped role |
| Manual `sed` substitution of ARNs into YAML | Helm charts with values files, or tools like Kustomize, or the AWS Controllers for Kubernetes (ACK) |
| `aws-cli:latest` image running in a loop | Application containers with the AWS SDK for your language (boto3, go-aws-sdk, aws-sdk-js) |
| OIDC provider created manually in Terraform | Often created automatically by EKS add-ons, or managed by the cluster platform team centrally |
| Bugs surfaced by reading logs | Bugs surfaced by Datadog / CloudWatch Insights / audit logs flagging `AccessDenied` metrics |
| You know there are 6 bugs | You know there's a ticket saying "pod can't reach AWS" and nothing else |
| Single cluster, one team | Multiple clusters (dev, staging, prod), OIDC providers per cluster, centralised IAM role catalogue |

---

## Common Mistakes

- **Using the kube2iam annotation format.** `iam.amazonaws.com/role` is a deprecated third-party tool pattern, not IRSA. Always `eks.amazonaws.com/role-arn`.
- **Forgetting to recreate the pod after annotation changes.** Pods cache their ServiceAccount binding at creation. Edit the SA, delete the pod, apply again.
- **Wildcard resources in pod IAM policies.** A compromised pod with `Resource: "*"` can access every bucket and table in the account. Always scope.
- **Using `oidc.eks` as the literal condition key prefix.** The prefix must be the **specific cluster's OIDC issuer URL** (minus `https://`). Each cluster has its own.
- **Forgetting to wait for IAM consistency.** Trust policy change didn't seem to work? Wait 30 seconds and try again.

---

## Cleanup — Reset to broken state (for re-running the lab)

If you want to run the lab again from scratch:

```bash
git checkout -- main.tf manifests/
```

This restores the broken starting state from GitHub without re-cloning.

### Command breakdown

| Command | What it does |
|---|---|
| `git checkout -- <file>` | Discard local modifications to `<file>` and restore the version from the last commit. The `--` disambiguates file paths from branch names. |

---

## ⚠️ FINAL DESTROY REMINDER ⚠️

**Have you run `./destroy.sh`?**

If yes — confirm with:

```bash
aws eks list-clusters --region eu-west-2
```

If this returns anything containing `lab-087`, **the destroy didn't finish**. Don't close the laptop until this returns empty.

If you haven't run it yet — run it now:

```bash
./destroy.sh
```
