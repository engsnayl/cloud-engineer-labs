# Lab 087 — Solution Walkthrough: EKS Pod Can't Access AWS (IRSA Misconfigured)

---

## ⚠️ DESTROY REMINDER — TOP OF FILE ⚠️

This lab provisions real EKS + NAT Gateway infrastructure. **Run `./destroy.sh` when finished.** Cost if forgotten overnight: ~£4-5. Cost over a weekend: ~£10+. There is another destroy reminder at the bottom of this file — you will be reminded again.

If `./destroy.sh` fails with `Permission denied`, run `chmod +x destroy.sh` first, or just use `bash destroy.sh`.

---

## TLDR — Plain English

**The problem:** A pod in Kubernetes needs to reach AWS services (S3 and DynamoDB). The mechanism that lets it do that is called **IRSA** — IAM Roles for Service Accounts. Think of IRSA as a trust handshake between Kubernetes and AWS: the pod gets a temporary signed ID card from Kubernetes, and AWS is configured to accept that ID card and swap it for real AWS credentials.

In this lab, that handshake is broken in **six places**. Three are on the AWS side (in Terraform), two are on the Kubernetes side (in YAML files), and one is a security problem (the IAM permissions are too wide open).

**The fix, in plain terms:**
1. AWS expects the ID card to be labelled for a service called `sts.amazonaws.com`. The code labels it for `ec2.amazonaws.com`. Fix the label in two places (the OIDC provider's accepted-list, and the IAM role's trust conditions).
2. AWS needs to know *which* Kubernetes cluster's ID cards to trust. The trust conditions use a placeholder string instead of the real cluster address. Use the real address.
3. The pod's permissions currently say "do anything to anything". Tighten them to "do these specific things to this one bucket and this one table".
4. The Kubernetes ServiceAccount has the wrong sticker on it — it's using an old-style sticker from a deprecated tool (kube2iam). Use the new-style sticker AWS actually looks for (`eks.amazonaws.com/role-arn`).
5. The pod is using the namespace's default ServiceAccount instead of the one we configured. Point it at the right one.

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

## Concept Primer — What is IRSA actually doing?

Skip this section if you're already comfortable with OIDC, JWTs, and federated identity. Otherwise read it carefully — the diagnostic steps below all reference these concepts.

### The two-worlds problem IRSA solves

You've got two completely separate worlds:

- **Kubernetes** — knows about pods, ServiceAccounts, namespaces. Has its own concept of identity.
- **AWS** — knows about IAM users, roles, access keys. Has its own concept of identity.

Neither knows about the other. AWS has never heard of your pod. Kubernetes has never heard of your IAM role. So how do you get a pod to make AWS API calls without baking AWS access keys into its filesystem?

The answer: **federated identity**. Kubernetes signs a piece of paper saying "I, this Kubernetes cluster, vouch that this pod is `app-service-account`". The pod hands that paper to AWS. AWS — having been pre-configured to trust this Kubernetes cluster's signature — reads the paper, agrees the pod is who it claims to be, and hands back temporary AWS credentials. **The pod never sees a long-lived AWS credential.** Just a temporary one valid for an hour.

### Three pieces of jargon you need to know

**OIDC (OpenID Connect)** — the *protocol* that defines how this signed-paper trust works. It's a generic internet standard, not specific to AWS or Kubernetes. The same protocol powers "Sign in with Google" buttons everywhere. OIDC defines an **issuer** (the entity signing the papers — in our case the EKS cluster), a **provider configuration** at a well-known URL telling the world how to verify signatures, and the **format** of the signed paper.

**JWT (JSON Web Token)** — the *format* of the signed paper. It's literally just JSON, base64-encoded, with a cryptographic signature on the end. Three parts separated by dots: `header.payload.signature`. The payload contains "claims" — `sub` (subject — who this token belongs to), `aud` (audience — who this token is intended for), `iss` (issuer — who signed it), `exp` (when it expires).

**STS (Security Token Service)** — AWS's service for issuing temporary credentials. The pod calls `sts:AssumeRoleWithWebIdentity` with its JWT, and STS hands back temporary access keys.

### The IRSA flow end-to-end

1. **Pod starts.** EKS sees the SA has the `eks.amazonaws.com/role-arn` annotation. It injects two env vars into the pod (`AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`) and mounts a JWT at `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`.
2. **Pod makes an AWS call** (e.g. `aws s3 ls`). The AWS SDK sees the env vars and goes "ah, IRSA mode".
3. **SDK reads the token file** — that's the JWT, signed by the EKS cluster's OIDC issuer.
4. **SDK calls AWS STS**: "Hi, here's a JWT. Please give me temporary credentials for role `eks-app-role`."
5. **AWS STS validates the JWT**:
   - Looks at the `iss` claim → finds the matching OIDC provider in IAM
   - Verifies the JWT signature against the public keys at the issuer URL
   - Checks the `aud` claim is in the OIDC provider's `client_id_list` — *first place this lab breaks*
   - Reads the role's trust policy
   - Checks `sub` and `aud` claims against the trust policy conditions — *second place this lab breaks*
6. **If everything checks out**, STS hands back temporary AWS credentials valid for 1 hour. SDK uses those for the actual S3/DynamoDB call.
7. **Token rotation** — every hour, Kubernetes rotates the JWT with a fresh one. The SDK refreshes its temporary credentials transparently.

### The passport-at-border-control analogy

If asked to explain IRSA in 30 seconds in an interview:

- **JWT** = passport (signed document proving your identity)
- **Kubernetes/OIDC issuer** = passport-issuing country
- **AWS STS** = border control
- **Trust policy** = visa rules ("we accept passports from this Kubernetes cluster, but only for citizens whose passport says they're `default/app-service-account`")
- **Temporary credentials** = the visa stamp, valid for an hour

---

## Step 1 — Deploy what you were given and reproduce the failure

**Why:** Before you touch anything, reproduce the reported problem. If you start editing code without seeing the failure yourself, you're guessing. You also want to know what *kind* of failure it is — does `terraform apply` even succeed? Does the pod start? Does it start and then fail at runtime?

```bash
cd cloud-engineer-labs/cloud-labs/lab-087-eks-irsa-service-account
terraform init
terraform apply
```

**What happens:** `terraform apply` runs for ~15 minutes (EKS clusters are slow to provision) and succeeds:

```
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.

Outputs:
app_role_arn = "arn:aws:iam::340752829546:role/eks-app-role"
cluster_name = "lab-087-cluster"
oidc_issuer = "https://oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47"
s3_bucket_name = "eks-app-data-5e4cffdf"
dynamodb_table_name = "app-state-5e4cffdf"
```

So the infrastructure layer is fine. The failure must be at the runtime layer — the pod actually trying to use the credentials.

### Command breakdown

| Command | What each part does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin and the VPC module. Reads `main.tf` and pulls whatever it needs into `.terraform/`. Run once per clone. |
| `terraform apply` | Reads all `.tf` files, asks AWS for current state, calculates the difference, shows you a plan, then prompts `yes` to proceed. Creates all 35 resources: VPC, EKS cluster, node group, OIDC provider, IAM roles and policies, S3 bucket, DynamoDB table. |

---

## Step 2 — Wire up kubectl to the new cluster

**Why:** You now have an EKS cluster but your `kubectl` doesn't know about it. You need to tell `kubectl` how to talk to it.

**Ask yourself:** *Where do I get the cluster name from?* It's an output of the Terraform run. You don't need to hardcode anything — let the code tell you.

```bash
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region)
kubectl get nodes
```

You should see:

```
NAME                                      STATUS   ROLES    AGE     VERSION
ip-10-0-1-16.eu-west-2.compute.internal   Ready    <none>   4m40s   v1.30.14-eks-bbe087e
```

One node, `Ready`, 4 minutes old. The node name is `ip-` plus its private IP — that's the AWS convention. The `<none>` under ROLES just means it's a worker node (no special control-plane role).

### Command breakdown

| Command | What each part does |
|---|---|
| `aws eks update-kubeconfig` | Appends a new context to your `~/.kube/config` file |
| `--name <cluster-name>` | Which EKS cluster to configure |
| `--region <region>` | Which AWS region the cluster is in |
| `$(terraform output -raw cluster_name)` | Shell substitution — runs the inner command and pastes its output into the outer command. `-raw` strips quotes so the output is usable directly |
| `kubectl get nodes` | Confirms kubectl can reach the cluster. If this fails, nothing else will work |

---

## Step 3 — See what's already running on the cluster

**Why:** You haven't deployed anything yet. But the cluster is fully functional — what's running on it?

```bash
kubectl get pods -A
```

```
NAMESPACE     NAME                      READY   STATUS    RESTARTS   AGE
kube-system   aws-node-v7772            2/2     Running   0          5m8s
kube-system   coredns-c7bbdfbb8-2dq2d   1/1     Running   0          9m
kube-system   coredns-c7bbdfbb8-v5cpj   1/1     Running   0          9m
kube-system   kube-proxy-gmssh          1/1     Running   0          5m8s
```

**You didn't deploy any of these.** EKS installs them automatically because the cluster can't function without them:

| Pod | What it does |
|---|---|
| `aws-node` | Amazon VPC CNI plugin. Handles pod networking on AWS — gives each pod a real VPC IP. The `2/2` means this pod has 2 containers, both ready |
| `coredns` × 2 | DNS for the cluster. Two replicas for redundancy. When your pod does `aws s3 ls`, it needs to resolve `s3.eu-west-2.amazonaws.com` — CoreDNS handles that |
| `kube-proxy` | Handles Service networking inside the cluster |

`kubectl get pods -A` shows all namespaces. `default` doesn't appear in the output because there's nothing in it yet. The `-A` flag = "all namespaces". Without it, `kubectl get pods` only shows the `default` namespace.

### The Kubernetes hierarchy in plain terms

If you're new to Kubernetes, the noun stack is confusing. Read it from outside in:

- **Cluster** (outermost) — the umbrella name for "all the EKS stuff that hangs together". Created by your `terraform apply`. Logical, not physical.
- **Node** — an actual EC2 instance, the t3.small. Real Linux running somewhere. You only have one in this lab; production clusters have dozens.
- **Pod** — a thin wrapper around one or more containers that need to live together (same network, same disk, same lifecycle). 99% of pods have exactly one container. You can mostly read "pod" as "container with extra Kubernetes paperwork".
- **Container** — the actual running workload. Where the work happens.

When you say `kubectl get pods`, you're asking "what application workloads are running across my whole fleet?" Kubernetes goes "here's what's on each node". You don't care which node each pod is on — that's Kubernetes' problem to solve. **You stop caring about specific machines.** That's the whole point of Kubernetes.

---

## Step 4 — Apply the Kubernetes manifests with the right values

**Why:** The YAML files in `manifests/` have placeholder strings like `REPLACE_WITH_ROLE_ARN`. You need to substitute the real values from Terraform outputs before applying.

```bash
ROLE_ARN=$(terraform output -raw app_role_arn)
BUCKET=$(terraform output -raw s3_bucket_name)
TABLE=$(terraform output -raw dynamodb_table_name)

sed -i "s|REPLACE_WITH_ROLE_ARN|$ROLE_ARN|" manifests/serviceaccount.yaml
sed -i "s|REPLACE_WITH_BUCKET_NAME|$BUCKET|" manifests/pod.yaml
sed -i "s|REPLACE_WITH_TABLE_NAME|$TABLE|" manifests/pod.yaml

# Sanity-check the substitutions worked
grep -c REPLACE manifests/*.yaml
```

If both files return `0`, substitution worked. If either returns a non-zero number, something is wrong with the placeholder format and we'd need to debug.

```bash
kubectl apply -f manifests/
kubectl get pods -A
```

```
pod/app-pod created
serviceaccount/app-service-account created
NAMESPACE     NAME                      READY   STATUS              RESTARTS   AGE
default       app-pod                   0/1     ContainerCreating   0          1s
kube-system   aws-node-v7772            2/2     Running             0          18m
...
```

Notice the new row at the top — `app-pod` in the `default` namespace. `0/1 ContainerCreating` means the node is in the middle of pulling the `amazon/aws-cli:latest` image from Docker Hub. Takes 30-60 seconds the first time.

### Command breakdown

| Command | What each part does |
|---|---|
| `sed -i "s|find|replace|" file` | In-place string substitution. `-i` means edit the file directly. `\|` is the delimiter (used instead of `/` because the replacement contains forward slashes in the ARN) |
| `kubectl apply -f manifests/` | Apply every YAML file in the directory. Creates the ServiceAccount and the Pod |
| `grep -c REPLACE` | Counts matches of "REPLACE" in each file. `0` means no placeholders remain |

---

## Step 5 — Watch the pod fail

**Why:** This is the moment of truth — seeing the actual failure with your own eyes, not what someone else reported in the ticket.

Wait 30-60 seconds for the pod to reach `Running`, then:

```bash
kubectl logs app-pod -n default --tail=20
```

```
=== Sun Apr 26 09:08:57 UTC 2026 ===
--- Testing S3 ---
aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials. You can configure credentials by running "aws login".
S3 call failed
--- Testing DynamoDB ---
aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials. You can configure credentials by running "aws login".
DynamoDB call failed
```

**Read what this is telling you:**

- The pod is running. It's not crashing, it's not stuck pulling an image, it's not OOMKilled. It's just calling AWS and getting told it has no credentials.
- "Unable to locate credentials" means the AWS SDK looked in all the usual places for credentials and found none.

### The places the AWS SDK looks for credentials, in order:

1. Environment variables (`AWS_ACCESS_KEY_ID`, etc.)
2. Shared credentials file (`~/.aws/credentials`)
3. **Web Identity Token File** (the IRSA mechanism) — set via `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` env vars
4. EC2 Instance Metadata Service

For IRSA to work, step 3 must be in play. The pod must have those env vars automatically injected by EKS. **If it doesn't, you know the Kubernetes side of the chain isn't getting recognised as IRSA.**

Let's check:

```bash
kubectl exec app-pod -n default -- env | grep -i aws
```

```
AWS_REGION=eu-west-2
```

**One env var.** No `AWS_ROLE_ARN`, no token file. **EKS has not recognised this pod as an IRSA pod at all.**

### Command breakdown

| Command | What each part does |
|---|---|
| `kubectl logs app-pod` | Streams the container's stdout/stderr |
| `--tail=20` | Show only the last 20 lines |
| `kubectl exec app-pod -- env` | Run `env` inside the container and print output. The `--` separates `kubectl` arguments from the command to run in the container |
| `\| grep -i aws` | Filter to lines containing "aws", case-insensitive |

---

## Step 6 — Why isn't EKS injecting IRSA env vars?

**Ask yourself:** *EKS injects those env vars only when the pod's ServiceAccount has a specific annotation. Does it?*

```bash
kubectl get serviceaccount app-service-account -n default -o yaml
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    iam.amazonaws.com/role: arn:aws:iam::340752829546:role/eks-app-role
  name: app-service-account
  namespace: default
```

**The annotation is there. But the *key* is wrong.**

**How would you know that?** EKS/IRSA looks for a specific annotation key: `eks.amazonaws.com/role-arn`. The annotation here is `iam.amazonaws.com/role` — that's a different annotation used by **kube2iam**, an older community project that predates IRSA. Somebody copied a Stack Overflow answer from the wrong era.

**Quick sanity check:** Search the AWS IRSA docs for the exact annotation key — it's `eks.amazonaws.com/role-arn`. Mismatched annotation = EKS never recognises the pod as IRSA = no env vars injected = `Unable to locate credentials`.

**That's bug #1 found. But there's also bug #2 in the same area — is the pod even using this ServiceAccount?**

```bash
kubectl get pod app-pod -n default -o jsonpath='{.spec.serviceAccountName}'
echo
```

Output: `default`

**The pod is using the cluster's `default` ServiceAccount, not `app-service-account`.** Even if the annotation were correct, the pod wouldn't pick it up — it's bound to a different SA entirely.

### What "default" means here

Every Kubernetes namespace has a built-in ServiceAccount called `default`. If you create a pod without specifying `serviceAccountName:`, it gets bound to the namespace's `default` SA automatically. Whoever wrote the pod manifest either forgot to set it, or set it to the literal string `default` thinking that meant "the default app SA we just created" — common confusion.

### Fix both Kubernetes bugs now

Edit `manifests/serviceaccount.yaml`:

```yaml
# Before
metadata:
  name: app-service-account
  namespace: default
  annotations:
    iam.amazonaws.com/role: arn:aws:iam::340752829546:role/eks-app-role

# After — only the annotation key changes
metadata:
  name: app-service-account
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::340752829546:role/eks-app-role
```

> **Common mistake — don't fall for this:** The annotation key and the namespace key sit visually adjacent in YAML. When focused on "fix the annotation", it's easy to accidentally change the namespace too. The namespace must remain `default` — that's where your pod lives, and that's what the IAM role's trust policy expects (`system:serviceaccount:default:app-service-account`). If you change it to anything else, IRSA breaks at the trust-policy stage even when everything else is right.

Edit `manifests/pod.yaml`:

```yaml
# Before
spec:
  serviceAccountName: default

# After
spec:
  serviceAccountName: app-service-account
```

Apply both fixes and recreate the pod (pods can't change `serviceAccountName` while running — it's an immutable field):

```bash
kubectl apply -f manifests/serviceaccount.yaml
kubectl delete pod app-pod -n default
kubectl apply -f manifests/pod.yaml

# Wait ~30s for the new pod to start
kubectl exec app-pod -n default -- env | grep -i aws
```

**Now you should see:**
```
AWS_REGION=eu-west-2
AWS_STS_REGIONAL_ENDPOINTS=regional
AWS_ROLE_ARN=arn:aws:iam::340752829546:role/eks-app-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

**Four env vars now instead of one.** EKS is recognising the pod as IRSA-eligible. The Kubernetes side of the chain is wired up.

### Command breakdown

| Command | What each part does |
|---|---|
| `kubectl get serviceaccount ... -o yaml` | Fetch the SA and print as YAML. Useful for spotting exact annotation keys |
| `-o jsonpath='{.spec.serviceAccountName}'` | Output only that one field using a JSONPath query. More precise than piping `grep` |
| `kubectl delete pod && kubectl apply` | Pods can't change SA binding while running — delete and recreate is the pattern |

---

## Step 7 — Check the logs again

```bash
kubectl logs app-pod -n default --tail=10
```

```
aws: [ERROR]: An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: Incorrect token audience
```

**Different error.** Progress — the pod is now trying to assume the IAM role, but AWS is rejecting it. Read the error word by word:

- **Was:** `NoCredentials: Unable to locate credentials` — pod had no IRSA env vars at all
- **Now:** `InvalidIdentityToken: Incorrect token audience` — pod has IRSA env vars, presented its JWT to STS, and STS rejected the token specifically because the audience claim is wrong

### What "token audience" means in plain English

When the pod calls AWS, the JWT inside the pod has an `aud` (audience) claim — it says "this token is intended to be used by `<audience>`". AWS STS checks that claim against the OIDC provider's `client_id_list` (the allow-list of valid audiences). If they don't match, you get `InvalidIdentityToken: Incorrect token audience`.

You can confirm this by decoding the JWT inside the pod (it's just base64-encoded JSON):

```bash
kubectl exec app-pod -n default -- sh -c 'cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | cut -d. -f2 | base64 -d 2>/dev/null'
```

```json
{
  "aud": ["sts.amazonaws.com"],
  "exp": 1777281819,
  "iss": "https://oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47",
  "sub": "system:serviceaccount:default:app-service-account",
  ...
}
```

**The token's audience is `sts.amazonaws.com`** — exactly correct for IRSA. So if AWS is rejecting it, AWS is configured to accept something different.

### Confirming from the AWS side

```bash
aws iam list-open-id-connect-providers
```

```json
{
  "OpenIDConnectProviderList": [
    {
      "Arn": "arn:aws:iam::340752829546:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47"
    }
  ]
}
```

Then ask AWS to show the provider's full config. **Don't paste `<arn-from-above>` literally** — that's a placeholder, and bash will interpret `<` as input redirection and throw a syntax error. Substitute the actual ARN:

```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::340752829546:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47
```

You'll see `ClientIDList: ["ec2.amazonaws.com"]`. **That's the bug.** AWS is configured to accept tokens for EC2; the JWT is asking for STS.

### The fix — `main.tf` line in `aws_iam_openid_connect_provider`

```hcl
# Before
client_id_list = ["ec2.amazonaws.com"]

# After
client_id_list = ["sts.amazonaws.com"]
```

```bash
terraform apply
```

You'll see one resource modified: `aws_iam_openid_connect_provider.eks`. Approve with `yes`. Wait ~30 seconds for IAM consistency, then:

```bash
kubectl logs app-pod -n default --tail=10
```

### Command breakdown

| Command | What each part does |
|---|---|
| `cut -d. -f2` | JWT has three parts separated by dots — `cut` extracts the 2nd part (the payload) |
| `base64 -d` | Decode base64 to get the JSON payload |
| `aws iam list-open-id-connect-providers` | List all OIDC providers in the account |
| `aws iam get-open-id-connect-provider --open-id-connect-provider-arn <real-arn>` | Show one provider's full config including `ClientIDList`. The `<...>` syntax in shell is real (input redirection) — never paste literal angle brackets, always substitute the real value |

---

## Step 8 — A new error appears

```bash
kubectl logs app-pod -n default --tail=10
```

```
aws: [ERROR]: An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Different layer of the chain failing.** Read what changed:

- **Was:** `InvalidIdentityToken: Incorrect token audience` — OIDC provider rejected the token outright
- **Now:** `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity` — OIDC provider accepted the token, but the IAM role's trust policy refused to let it assume the role

We're past OIDC validation. Stuck at the trust policy.

### Inspect the trust policy

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
                "Federated": "arn:aws:iam::340752829546:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47"
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

**Two bugs in the Condition block.**

### Bug A — the condition key prefix is wrong

Look at the keys: `oidc.eks:sub` and `oidc.eks:aud`. Those are literally the strings `oidc.eks:sub` and `oidc.eks:aud`. Gibberish.

For IAM to evaluate JWT claims, the condition key must be **the full OIDC issuer URL of the cluster, without `https://`, followed by `:sub` or `:aud`.** For your cluster:

```
oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47:sub
oidc.eks.eu-west-2.amazonaws.com/id/443D5067F61A3DD66610FCA33A687D47:aud
```

A single AWS account can have multiple OIDC providers — multiple EKS clusters, GitHub Actions, Bitbucket Pipelines. Each issues tokens with their own claims. The issuer-URL prefix tells AWS *which* issuer's claims this trust policy is evaluating. `oidc.eks:sub` doesn't refer to any real issuer, so AWS can't find any claims to compare against — condition fails — `AccessDenied`.

### Bug B — the `aud` value is wrong

```
"oidc.eks:aud": "ec2.amazonaws.com"
```

The trust policy demands the JWT's `aud` claim equal `ec2.amazonaws.com`. The JWT actually says `sts.amazonaws.com`. Even if Bug A were fixed, this condition would still fail. Same logical bug as the OIDC `client_id_list` you just fixed (someone thought IRSA was for EC2; it's for STS) — manifesting in two different places.

### The fix — `main.tf` `aws_iam_role.app_role`

```hcl
# Before
Condition = {
  StringEquals = {
    "oidc.eks:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
    "oidc.eks:aud" = "ec2.amazonaws.com"
  }
}

# After
Condition = {
  StringEquals = {
    "${local.oidc_issuer_stripped}:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
    "${local.oidc_issuer_stripped}:aud" = "sts.amazonaws.com"
  }
}
```

**Why use `local.oidc_issuer_stripped` rather than hardcoding the URL?**

- **Repeatability** — `terraform destroy` and `terraform apply` again creates a new EKS cluster with a new OIDC issuer ID. The local value updates automatically; a hardcoded URL would be stale.
- **Portability** — same code works in any region or account.
- **Readability** — variable name tells you what it is.

The local is already defined at the top of `main.tf`:
```hcl
oidc_issuer_stripped = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
```

```bash
terraform apply
```

One resource modified: `aws_iam_role.app_role`. Approve with `yes`. Wait ~30 seconds for IAM consistency.

---

## Step 9 — Verify the pod works

```bash
kubectl logs app-pod -n default --tail=10
```

```
=== Sun Apr 26 09:38:42 UTC 2026 ===
--- Testing S3 ---
2026-04-26 09:30:00          0 test-object.txt
--- Testing DynamoDB ---
{
    "Item": {
        "id": { "S": "test-id" },
        "value": { "S": "hello from irsa lab" }
    }
}
```

**The IRSA chain is fully wired up.** All five functional bugs fixed:

1. ✅ ServiceAccount annotation key (kube2iam → IRSA)
2. ✅ Pod's `serviceAccountName` (default → app-service-account)
3. ✅ OIDC provider's `client_id_list` (ec2 → sts)
4. ✅ Trust policy condition keys (gibberish prefix → real OIDC issuer URL)
5. ✅ Trust policy `aud` value (ec2 → sts)

But the ticket isn't closed yet. Reread it:

> Security team wants the IAM policy tightened before they sign off.

That's bug #6.

---

## Step 10 — The security finding

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

**`Resource = "*"` means this role can read/write every S3 bucket and every DynamoDB table in the account.** If this pod is ever compromised — supply chain attack, code injection, leaked secret — an attacker gets a foothold across your entire data plane.

### The fix — scope to specific resources

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

### Why two ARNs for S3 specifically

This trips a lot of people up. In AWS, S3 has two distinct levels of ARN:

| ARN format | What it identifies | Actions that need this |
|---|---|---|
| `arn:aws:s3:::bucket-name` | The bucket itself | `s3:ListBucket`, `s3:GetBucketLocation`, `s3:DeleteBucket` |
| `arn:aws:s3:::bucket-name/*` | Every object inside | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` |

If you only had the bucket ARN, `s3:GetObject` would fail because no object matches. If you only had the wildcard ARN, `s3:ListBucket` would fail because the bucket itself isn't an object. **You need both.**

DynamoDB doesn't have this split — items are accessed via the table's ARN, not as separate ARNs. One ARN covers everything.

### Why use Terraform attribute references instead of hardcoded ARNs?

The bucket name includes a random suffix (`eks-app-data-5e4cffdf`) that changes every time you `terraform destroy && terraform apply`. Hardcoded ARNs would be stale after one cycle. `aws_s3_bucket.app_data.arn` resolves at plan time to the current ARN — always correct.

```bash
terraform apply
```

One resource modified: `aws_iam_role_policy.app_permissions`. Approve. Wait ~30 seconds, then verify the pod still works:

```bash
kubectl logs app-pod -n default --tail=10
```

You should still see successful S3 and DynamoDB operations — same as before. If you see `AccessDenied` on either, the resource scoping is wrong (probably forgot the `/*` ARN for S3).

---

## Step 11 — Validate

```bash
lab validate 087
```

You should see all 11 checks pass. The validator checks the full chain: Terraform validity, OIDC `ClientIDList` against AWS, trust policy condition keys, trust policy aud value, IAM policy resource scoping, ServiceAccount annotation, pod SA reference, pod is Running, pod successfully calls S3, pod successfully calls DynamoDB, no credential errors in recent logs.

If any check fails, read the failure and go back to the relevant step.

### Validator design notes

This validator queries AWS directly rather than parsing Terraform's state output. That's a deliberate choice — `terraform state show` formats fields like `client_id_list` across multiple lines, which makes line-based grep unreliable. When verifying cloud resource configuration, query the cloud directly with `aws iam get-open-id-connect-provider` etc. — you get the canonical state in JSON, easy to filter with `--query`. Validators that grep human-readable Terraform output are fragile.

---

## Step 12 — 🚨 TEAR DOWN THE INFRASTRUCTURE 🚨

**Do this now, before you do anything else.**

```bash
chmod +x destroy.sh   # if you get Permission denied
./destroy.sh
```

Or just:
```bash
bash destroy.sh
```

The script:
1. Deletes K8s resources (`kubectl delete -f manifests/`)
2. Empties the S3 bucket (`aws s3 rm --recursive`)
3. Runs `terraform destroy`
4. Verifies no EKS clusters, NAT Gateways, or OIDC providers remain

If destroy fails partway through, **do not ignore it**. Common causes:
- S3 bucket not empty → `aws s3 rm s3://<bucket> --recursive` manually
- IAM eventual consistency → wait 30 seconds and rerun
- Kubernetes finalizers hanging → `kubectl delete pod app-pod --force`

After the script succeeds, sanity-check:

```bash
aws eks list-clusters --region eu-west-2
aws ec2 describe-nat-gateways --region eu-west-2 --filter "Name=state,Values=available,pending"
```

Both should return empty.

---

## Diagnostic Chain You Walked

This is the kind of thing you'd describe in an interview: "describe a time you debugged IAM/OIDC in production". The diagnostic walk had a clear pattern — each error message pointed at the next layer:

| Symptom | What it told you | Where to look next |
|---|---|---|
| `NoCredentials: Unable to locate credentials` | Pod has no AWS env vars | ServiceAccount annotation |
| `kubectl exec env \| grep aws` shows only `AWS_REGION` | EKS doesn't recognise pod as IRSA | SA annotation key + pod's SA reference |
| `InvalidIdentityToken: Incorrect token audience` | OIDC provider doesn't accept the token's aud | OIDC provider `client_id_list` |
| `AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy conditions don't match | Trust policy condition keys + aud value |
| Pod logs S3 ls output and DynamoDB JSON | IRSA chain working end to end | Done — but check security |
| Wildcard `Resource = "*"` in IAM policy | Audit finding | Scope to specific ARNs |

**Fixing the bug closer to Kubernetes (annotation, SA reference) revealed the next bug closer to AWS (OIDC client list).** Fixing that revealed the trust policy bug. That's how IRSA debugging always works — the chain has multiple links and each one breaks the chain entirely. You can't shortcut it; you walk each link.

---

## Lab vs Real Life

| Lab | Real Life |
|---|---|
| One pod, one bucket, one table | Dozens of pods across multiple namespaces, each with their own scoped role |
| Manual `sed` substitution of ARNs into YAML | Helm charts with values files, Kustomize, or AWS Controllers for Kubernetes (ACK) |
| `aws-cli:latest` image running in a loop | Application containers with the AWS SDK for your language |
| OIDC provider created manually in Terraform | Often created automatically by the EKS module, or managed centrally by a platform team |
| Bugs surfaced by reading logs | Bugs surfaced by Datadog/CloudWatch Insights/audit logs flagging `AccessDenied` metrics |
| You know there are 6 bugs | You know there's a ticket saying "pod can't reach AWS" and nothing else |
| Single cluster, one team | Multiple clusters (dev, staging, prod), OIDC providers per cluster, centralised IAM role catalogue |

---

## Common Mistakes

- **kube2iam annotation format.** `iam.amazonaws.com/role` is a deprecated third-party tool pattern. Always `eks.amazonaws.com/role-arn` for IRSA.
- **Editing the namespace key by accident when fixing the annotation.** They sit visually adjacent in YAML. Namespace must remain `default` for this lab.
- **Forgetting to recreate the pod after annotation changes.** Pods cache their SA binding at creation. Edit the SA, delete the pod, apply again.
- **Pasting `<placeholder-text>` literally in shell commands.** Angle brackets `<` `>` are real bash operators (input/output redirection). Substitute the actual value.
- **Wildcard resources in pod IAM policies.** A compromised pod with `Resource: "*"` can access every bucket and table in the account. Always scope.
- **Using `oidc.eks` as the literal condition key prefix.** The prefix must be the **specific cluster's OIDC issuer URL** (minus `https://`). Each cluster has its own.
- **Forgetting to wait for IAM consistency.** Trust policy change didn't seem to work? Wait 30 seconds and try again before assuming you got it wrong.

---

## Cleanup — Reset to broken state (for re-running the lab)

```bash
git checkout -- main.tf manifests/
```

Restores the broken starting state from GitHub without re-cloning.

---

## ⚠️ FINAL DESTROY REMINDER ⚠️

**Have you run `./destroy.sh`?**

If yes — confirm:

```bash
aws eks list-clusters --region eu-west-2
```

If this returns anything containing `lab-087`, **the destroy didn't finish**. Don't close the laptop until this returns empty.

If you haven't run it yet — run it now.
