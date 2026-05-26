# Phase 1 Plan — Interview Drill Runner (MCQ)

Source-by-source allocation and concept-angle outlines for the 3 MCQ banks.
**No MCQs authored yet** — this is the sign-off gate before Phase 2.

## Inputs

- **Source file:** `Interview Prep App/Interview-Prep-Combined.md`
  - Note: the brief's raw URL `https://raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` returns 404 (private or moved), so this plan uses the local copy already present in the labs repo. Counts match the brief exactly.
- **Sources parsed:** 110 total → 104 after excluding 6 behavioural items (`beh-001`–`beh-006`)
- **Target MCQs:** 2 per source × 104 sources = **208 MCQs across 3 banks**

## Domain totals (matches Section 2 of the brief)

| Domain | Source questions | MCQs (×2) |
|---|---|---|
| AWS | 28 | 56 |
| Kubernetes | 22 | 44 |
| CI/CD | 18 | 36 |
| Terraform | 13 | 26 |
| Docker | 10 | 20 |
| Linux | 7 | 14 |
| Git | 6 | 12 |
| **Total** | **104** | **208** |

## Bank composition

Bank totals: Bank 1 = **70**, Bank 2 = **69**, Bank 3 = **69**.

| Domain | Bank 1 | Bank 2 | Bank 3 | Brief target |
|---|---|---|---|---|
| AWS | 19 | 19 | 18 | 18-19 |
| Kubernetes | 15 | 14 | 15 | 14-15 |
| CI/CD | 12 | 12 | 12 | 12 |
| Terraform | 8 | 9 | 9 | 8-9 |
| Docker | 7 | 6 | 7 | 6-7 |
| Linux | 5 | 5 | 4 | 4-5 |
| Git | 4 | 4 | 4 | 4 |
| **Total** | **70** | **69** | **69** | ~69 |

### Priority spread per bank

Every bank contains a mix of critical / high / medium so each Interview feels representative. Low (2 sources total) is in banks 2 and 3.

| Bank | critical | high | medium | low |
|---|---|---|---|---|
| 1 | 18 | 32 | 20 | 0 |
| 2 | 16 | 30 | 21 | 2 |
| 3 | 14 | 26 | 27 | 2 |

## Allocation strategy

For each source, the **2 MCQs go into different banks** (per brief Section 3.2). That pair is one of `(1,2)`, `(1,3)`, or `(2,3)`. Domain capacities and pair-type quotas are solved algebraically so the per-bank-per-domain totals match the table above.

**Pair-type quotas per domain** (each entry = number of sources assigned that pair):

| Domain | (1,2) | (1,3) | (2,3) |
|---|---|---|---|
| AWS | 10 | 9 | 9 |
| Kubernetes | 7 | 8 | 7 |
| CI/CD | 6 | 6 | 6 |
| Terraform | 4 | 4 | 5 |
| Docker | 3 | 4 | 3 |
| Linux | 3 | 2 | 2 |
| Git | 2 | 2 | 2 |

Within each domain, sources are sorted by priority (critical → high → medium → low) and assigned round-robin across pair types so every bank gets a healthy slice of the high-priority material.

## Per-source allocation and concept angles

Each row lists the source, its priority, which two banks its MCQs go to (MCQ 1 → lower-numbered bank, MCQ 2 → higher), and one-sentence outlines for each MCQ. Outlines are deliberately distinct facets so the two MCQs don't duplicate each other.

### AWS (28 sources → 56 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `aws-001` | C | 1+2 | _(B1)_ Subnet placement rules: which tier sits in public vs private subnets, and why | _(B2)_ Tier-to-tier security group chaining as the enforcement layer between web/app/data |
| `aws-002` | H | 1+2 | _(B1)_ Route table with 0.0.0.0/0 to IGW as the actual public/private differentiator | _(B2)_ NAT Gateway vs Internet Gateway placement and direction of traffic |
| `aws-003` | C | 1+3 | _(B1)_ Stateful SG vs stateless NACL: return-traffic behaviour after an inbound allow | _(B3)_ Rule evaluation order and default deny vs default allow between the two controls |
| `aws-005` | H | 1+3 | _(B1)_ Multi-AZ synchronous standby vs read replica asynchronous lag and failover semantics | _(B3)_ Choosing read scaling vs HA for a given workload — common misuse of read replicas for HA |
| `aws-007` | H | 2+3 | _(B2)_ RTO/RPO trade-offs across Backup / Pilot Light / Warm Standby / Multi-Site Active | _(B3)_ Picking the right DR pattern under a stated cost vs availability constraint |
| `aws-008` | M | 1+2 | _(B1)_ S3 storage class fit: Standard vs IA vs Glacier Instant vs Glacier Deep Archive | _(B2)_ Lifecycle policy gotchas: minimum storage duration and retrieval cost charges |
| `aws-009` | M | 1+3 | _(B1)_ Block (EBS) vs file (EFS) vs file-protocol (FSx) selection by access pattern | _(B3)_ Single-attach vs multi-attach: EBS Multi-Attach caveats vs EFS shared access |
| `aws-010` | H | 1+2 | _(B1)_ Block Public Access vs bucket policy: which wins when they disagree | _(B2)_ Bucket policy vs IAM policy interaction for cross-account S3 access |
| `aws-012` | H | 1+3 | _(B1)_ ALB Layer 7 routing capabilities vs NLB Layer 4 use cases | _(B3)_ Picking ALB vs NLB vs GWLB for TLS termination, WebSocket, or low-latency UDP |
| `aws-013` | M | 2+3 | _(B2)_ What deregistration delay actually does to in-flight connections | _(B3)_ Impact of connection draining on rolling deploys and ASG scale-in events |
| `aws-014` | H | 2+3 | _(B2)_ Inbound vs outbound capability: IGW (both) vs NAT Gateway (outbound only) | _(B3)_ Cost and AZ-resilience trade-offs: NAT Gateway per-AZ vs single-AZ NAT instance |
| `aws-015` | H | 1+2 | _(B1)_ VPC Peering's non-transitive routing limit vs Transit Gateway hub-and-spoke | _(B2)_ PrivateLink as service-not-VPC exposure (one-way endpoint into a service) |
| `aws-016` | M | 1+2 | _(B1)_ Latency vs Geolocation vs Geoproximity routing — distinct decision inputs | _(B2)_ Failover routing policy and the health check requirement that makes it work |
| `aws-017` | H | 1+3 | _(B1)_ Gateway endpoint (S3, DynamoDB only) vs Interface endpoint (PrivateLink) | _(B3)_ VPC endpoints as NAT-cost avoidance and the DNS resolution behaviour they require |
| `aws-019` | M | 1+3 | _(B1)_ Instance family naming (M/C/R/G) and how to map workload profile to family | _(B3)_ Right-sizing methodology: CloudWatch metrics + Compute Optimizer recommendations |
| `aws-020` | H | 2+3 | _(B2)_ Target tracking vs step scaling: which fits steady demand vs spiky demand | _(B3)_ Cooldown periods and scale-in protection semantics during deployments |
| `aws-021` | H | 1+2 | _(B1)_ When Spot is appropriate: workload interruption tolerance and checkpointing | _(B2)_ RI vs Savings Plan: discount magnitude vs flexibility (instance family lock-in) |
| `aws-022` | C | 2+3 | _(B2)_ When Lambda is the wrong answer: 15-min limit, cold start, sustained workloads | _(B3)_ ECS vs EKS operational overhead — when EKS earns its complexity |
| `aws-024` | H | 1+3 | _(B1)_ First-action playbook: Cost Explorer + tagging analysis before architectural changes | _(B3)_ Pricing-model levers (RI/SP/Spot) vs architectural levers (right-size, S3 tier) by impact |
| `aws-026` | C | 1+2 | _(B1)_ When to use a role vs a user: workload identity and EC2/Lambda assume-role | _(B2)_ Long-term IAM user credentials vs temporary STS credentials and the rotation problem |
| `aws-027` | M | 2+3 | _(B2)_ Managed vs customer-managed vs inline: reusability and operational trade-offs | _(B3)_ Permissions boundary vs SCP vs identity policy — where each is enforced |
| `aws-028` | M | 1+2 | _(B1)_ Cross-account role assume: trust policy in target + sts:AssumeRole in source | _(B2)_ External ID as the confused deputy mitigation in third-party access patterns |
| `aws-029` | H | 2+3 | _(B2)_ Automatic rotation: Secrets Manager native integration with RDS vs Parameter Store manual | _(B3)_ Cost per secret/parameter vs feature parity — when Parameter Store is enough |
| `aws-030` | H | 1+2 | _(B1)_ Standard vs high-resolution metrics and custom metric cost per metric | _(B2)_ Composite alarms vs threshold alarms for noise reduction in incident channels |
| `aws-031` | C | 1+3 | _(B1)_ First commands to run on a 90% CPU EC2 instance (top/htop, vmstat, pidstat) | _(B3)_ Distinguishing symptom from cause: traffic spike vs runaway thread vs noisy neighbour |
| `aws-032` | C | 2+3 | _(B2)_ Where latency hides in a 3-tier app: DNS, LB, app, DB, downstream service | _(B3)_ Distributed tracing (X-Ray) vs metric-only investigation for slow requests |
| `aws-034` | M | 1+3 | _(B1)_ What actually happens during a Lambda cold start (init phase + package load) | _(B3)_ Provisioned Concurrency vs SnapStart vs runtime choice — distinct mitigations |
| `aws-035` | M | 2+3 | _(B2)_ REST vs HTTP API: feature parity, cost, and which to pick for a new build | _(B3)_ Lambda proxy integration vs HTTP_PROXY vs AWS service integration patterns |

### Kubernetes (22 sources → 44 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `k8s-001` | C | 1+2 | _(B1)_ What each abstraction owns: Deployment manages ReplicaSet manages Pods | _(B2)_ When you'd ever hand-create a ReplicaSet vs a Deployment in practice |
| `k8s-002` | H | 1+2 | _(B1)_ Pod phase transitions: Pending → Running → Succeeded/Failed and what each means | _(B2)_ Where pods get stuck: Pending = scheduling vs CrashLoopBackOff = container exit |
| `k8s-003` | H | 1+3 | _(B1)_ Liveness vs readiness vs startup probe: what each triggers when it fails | _(B3)_ Misconfigured liveness probe that restarts a slow-starting app on every boot |
| `k8s-004` | M | 1+2 | _(B1)_ Init container ordering and how it blocks main container start | _(B2)_ Native sidecar containers (1.28+): restartPolicy: Always init and lifecycle ordering |
| `k8s-005` | C | 1+3 | _(B1)_ CPU throttle (compressible) vs memory OOMKilled (incompressible) under limit pressure | _(B3)_ QoS class assignment (Guaranteed / Burstable / BestEffort) and eviction order |
| `k8s-010` | C | 2+3 | _(B2)_ ClusterIP vs NodePort vs LoadBalancer vs ExternalName exposure scope | _(B3)_ When to use Ingress instead of multiple LoadBalancer services |
| `k8s-011` | H | 2+3 | _(B2)_ Ingress object vs Ingress controller (you need both, controller is the implementation) | _(B3)_ Host-based vs path-based routing and where TLS termination happens |
| `k8s-012` | M | 1+3 | _(B1)_ Default-allow until a NetworkPolicy selects the pod, then default-deny within scope | _(B3)_ CNI requirement: VPC CNI native vs Calico/Cilium for NetworkPolicy support |
| `k8s-013` | M | 2+3 | _(B2)_ CoreDNS as the cluster resolver and service-name FQDN format (svc.ns.svc.cluster.local) | _(B3)_ Pod DNS resolution flow and ndots/search domains gotcha for cross-namespace lookups |
| `k8s-014` | M | 1+3 | _(B1)_ DNS-based discovery vs env-var injection (env vars are start-time-only) | _(B3)_ ExternalName services for integrating external endpoints into in-cluster DNS |
| `k8s-020` | C | 1+2 | _(B1)_ Workload type fit: Deployment vs StatefulSet vs DaemonSet vs Job by requirement | _(B2)_ StatefulSet specifics: stable network identity, ordered rollout, persistent volume claim per pod |
| `k8s-021` | H | 1+2 | _(B1)_ Taints/tolerations as exclusion vs nodeSelector/affinity as inclusion | _(B2)_ required vs preferred affinity and using anti-affinity for HA across nodes/AZs |
| `k8s-022` | H | 1+3 | _(B1)_ PDB blocks voluntary disruption only (node drain) — not pod crashes | _(B3)_ Pre-stop hook + terminationGracePeriodSeconds role in clean shutdown |
| `k8s-023` | C | 1+3 | _(B1)_ HPA (replica count) vs VPA (resource size) vs Cluster Autoscaler (node count) dimensions | _(B3)_ Karpenter just-in-time provisioning vs Cluster Autoscaler ASG-bound model |
| `k8s-030` | H | 2+3 | _(B2)_ Secrets are base64-encoded, not encrypted — and what KMS envelope encryption actually adds | _(B3)_ When to use ConfigMap vs Secret and the 1 MiB size limit on both |
| `k8s-031` | M | 2+3 | _(B2)_ External Secrets Operator vs Secrets Store CSI Driver: pull-on-mount vs sync-to-Secret | _(B3)_ IRSA wiring for a pod to fetch from AWS Secrets Manager without static credentials |
| `k8s-032` | H | 1+2 | _(B1)_ Role/RoleBinding vs ClusterRole/ClusterRoleBinding and which combinations are legal | _(B2)_ Cluster-scoped vs namespace-scoped permissions and least-privilege patterns |
| `k8s-040` | C | 2+3 | _(B2)_ EKS shared-responsibility split: AWS manages control plane, you manage workloads | _(B3)_ Managed node groups vs Fargate vs Karpenter — when each is the right compute choice |
| `k8s-041` | C | 1+2 | _(B1)_ IRSA mechanics: OIDC provider on cluster + projected service-account JWT token | _(B2)_ IRSA vs EKS Pod Identity: agent-based vs OIDC-based and migration considerations |
| `k8s-042` | H | 1+3 | _(B1)_ VPC CNI assigns real VPC IPs to pods, so pod density is ENI×IP-per-ENI bound | _(B3)_ Mitigations: prefix delegation (recommended) vs custom networking vs IPv6 |
| `k8s-050` | C | 1+3 | _(B1)_ Pending = scheduler can't place (resources / affinity) vs ImagePullBackOff = registry/auth | _(B3)_ CrashLoopBackOff investigation order: previous-pod logs, exit code, then describe |
| `k8s-051` | H | 2+3 | _(B2)_ Where latency hides in a K8s service path: DNS, kube-proxy, CNI overhead, app, downstream | _(B3)_ Tooling fit: kubectl top vs describe vs exec — which to reach for first |

### CI/CD (18 sources → 36 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `cicd-001` | H | 1+2 | _(B1)_ Continuous Delivery (deployable to prod) vs Continuous Deployment (automatic to prod) | _(B2)_ Where CI ends and CD begins: artifact promotion as the handoff |
| `cicd-002` | C | 1+2 | _(B1)_ Stage ordering: fail-fast linters and unit tests before slow integration tests | _(B2)_ Parallelisation strategy and the speed vs thoroughness trade-off in pipeline design |
| `cicd-003` | M | 1+3 | _(B1)_ Why long-lived feature branches break CI/CD (drift, merge-hell, stale tests) | _(B3)_ Feature flags as the mechanism that decouples deploy from release in trunk-based |
| `cicd-010` | C | 1+3 | _(B1)_ Workflow → job → step → runner hierarchy and where each piece of config lives | _(B3)_ GitHub-hosted vs self-hosted runners: cost, security, and isolation trade-offs |
| `cicd-011` | H | 1+3 | _(B1)_ Reusable workflows (separate workflow file, separate run) vs composite actions (inline) | _(B3)_ Picking reusable workflow vs composite action by need for secrets/contexts and reuse scope |
| `cicd-012` | M | 2+3 | _(B2)_ Matrix expansion semantics: cross-product of declared dimensions | _(B3)_ Cost-aware matrix design with include / exclude rules to prune wasteful combinations |
| `cicd-013` | H | 2+3 | _(B2)_ Cache key strategy: hashing lock files for stability and invalidation control | _(B3)_ Docker layer caching: BuildKit cache mounts and registry-backed cache for multi-runner |
| `cicd-014` | C | 2+3 | _(B2)_ Secret scoping: repo vs org vs environment, and the blast-radius implication | _(B3)_ Environment protection rules: required reviewers and wait timers as deploy gates |
| `cicd-020` | C | 1+2 | _(B1)_ Why OIDC beats static IAM access keys (no long-lived secret, audit trail per run) | _(B2)_ Trust policy sub-claim restrictions (branch, environment) to prevent token misuse |
| `cicd-021` | H | 1+2 | _(B1)_ kubectl apply vs Helm vs kustomize trade-offs in a deploy pipeline | _(B2)_ Push-based (kubectl from CI) vs pull-based (Argo CD / Flux GitOps) deployment models |
| `cicd-022` | H | 1+3 | _(B1)_ Task definition revisioning and how ECS rolling update progresses | _(B3)_ ECS rolling update vs CodeDeploy blue/green: when the latter earns its complexity |
| `cicd-030` | C | 1+3 | _(B1)_ Rolling vs blue-green vs canary: risk, cost, and rollback-speed trade-offs | _(B3)_ Feature flags as a complementary mechanism (release ≠ deploy) |
| `cicd-031` | H | 2+3 | _(B2)_ Expand-contract pattern: additive schema change first, app cutover, then contract | _(B3)_ Backwards-compatibility window: app must read old + new schema during deploy |
| `cicd-032` | H | 1+2 | _(B1)_ Automated rollback triggers: health-check failure thresholds vs error-rate alarms | _(B2)_ Why database changes resist rollback and the forward-fix bias in mature pipelines |
| `cicd-040` | H | 1+3 | _(B1)_ SAST vs DAST vs SCA vs container scanning — what class of issue each catches | _(B3)_ Where in the pipeline each scan runs (commit, build, pre-deploy, runtime) |
| `cicd-041` | M | 2+3 | _(B2)_ Quality gate semantics: new-code metrics vs whole-codebase metrics in PR gating | _(B3)_ Integration shape with GitHub Actions: pull-request decoration and gate enforcement |
| `cicd-050` | C | 2+3 | _(B2)_ Distinguishing flaky tests from real failures: re-run patterns and quarantine | _(B3)_ Common flake sources: timing, parallel shared state, network, container start delays |
| `cicd-051` | C | 1+2 | _(B1)_ Design priorities a pipeline owner balances: speed, signal, cost, security | _(B2)_ Trade-offs and lessons from a real pipeline (what you'd do differently next time) |

### Terraform (13 sources → 26 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `tf-001` | C | 1+2 | _(B1)_ Plan / apply / destroy lifecycle and what state contributes at each step | _(B2)_ Terraform vs CloudFormation / CDK trade-offs: multi-cloud, HCL ergonomics, drift |
| `tf-002` | C | 1+3 | _(B1)_ DynamoDB state locking is advisory and fail-fast (not a queue) | _(B3)_ Why remote state and why state files contain sensitive data (encrypt the bucket) |
| `tf-003` | H | 1+2 | _(B1)_ Module interface design: clear inputs / outputs / required-providers contract | _(B2)_ Module versioning and registry usage (semantic versions in source = ref=) |
| `tf-004` | M | 1+2 | _(B1)_ Variable precedence: CLI -var > -var-file > env TF_VAR_ > terraform.tfvars > defaults | _(B2)_ Locals (computed inside config) vs variables (user input) — when each is right |
| `tf-005` | H | 1+3 | _(B1)_ Workspaces caveat: single backend, similar configs only — not a prod isolation tool | _(B3)_ Separate-state per env vs workspaces vs Terragrunt-style DRY for env management |
| `tf-006` | M | 1+3 | _(B1)_ Why tfvars + .gitignore is risky: secrets still land in state files | _(B3)_ Data source pattern: fetch secrets at apply time from Secrets Manager / Vault |
| `tf-007` | L | 2+3 | _(B2)_ Why provisioners are an antipattern: state lies about provisioned-but-not-converged | _(B3)_ When local-exec / remote-exec is genuinely justified (and the better alternatives) |
| `tf-008` | M | 2+3 | _(B2)_ terraform refresh updates state to reality; apply changes reality to match config | _(B3)_ How drift gets introduced (out-of-band changes) and reconciliation options |
| `tf-009` | H | 2+3 | _(B2)_ Plan-on-PR / apply-on-merge pattern and the role of human approval | _(B3)_ State-lock contention in CI: parallel runs, cancelled apply, and orphan locks |
| `tf-010` | L | 2+3 | _(B2)_ Provisioning live infra (Terraform) vs baking machine images (Packer) | _(B3)_ Golden-image workflow: Packer builds AMI → Terraform consumes via data source |
| `tf-011` | M | 1+3 | _(B1)_ Index-addressed (count) vs key-addressed (for_each) resource stability | _(B3)_ The classic count problem: removing a middle item recreates all subsequent resources |
| `tf-012` | M | 2+3 | _(B2)_ moved block (TF 1.1+) for in-config renames without destroy/create | _(B3)_ terraform state mv vs import: when each applies during refactors |
| `tf-013` | H | 1+2 | _(B1)_ Common investigation steps: plan inspection, TF_LOG, state file diff | _(B2)_ Drift vs config bug vs provider bug — diagnosis path for ambiguous errors |

### Docker (10 sources → 20 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `docker-001` | H | 1+2 | _(B1)_ Kernel-shared (containers, namespaces+cgroups) vs hardware-virtualised (VMs) isolation | _(B2)_ Resource overhead and start-time differences and where each fits |
| `docker-002` | C | 1+2 | _(B1)_ Layer order for cache reuse: copy lock files and install deps before copying source | _(B2)_ Non-root USER + minimal base image + COPY --chown for least-privilege containers |
| `docker-003` | H | 1+3 | _(B1)_ Build vs runtime stage separation so build toolchain doesn't ship in the final image | _(B3)_ Multi-stage as a build-time secret containment pattern (secrets stay in earlier stages) |
| `docker-004` | M | 1+3 | _(B1)_ Alpine vs distroless vs full OS base: trade-offs in glibc compatibility and debuggability | _(B3)_ .dockerignore + dependency pruning + single-RUN apt-get to keep layers small |
| `docker-005` | M | 2+3 | _(B2)_ Cache invalidation rule: any change in a COPY busts that layer and every layer after | _(B3)_ BuildKit improvements: cache mounts, parallel stage execution, secret mounts |
| `docker-006` | M | 1+3 | _(B1)_ Bridge vs host vs none vs custom network — semantics of each | _(B3)_ Container-name DNS resolution on user-defined networks (not default bridge) |
| `docker-007` | M | 2+3 | _(B2)_ Bind mounts (host-path coupled) vs named volumes (portable across hosts) | _(B3)_ tmpfs use case: in-memory secrets / ephemeral scratch space |
| `docker-008` | M | 1+3 | _(B1)_ Compose scope: dev and single-host orchestration — not a Kubernetes replacement | _(B3)_ Compose service dependencies (depends_on, healthcheck) and default network behaviour |
| `docker-009` | H | 2+3 | _(B2)_ ECR auth via aws ecr get-login-password — short-lived token, must re-auth | _(B3)_ Lifecycle policies for image pruning and tag immutability for reproducible deploys |
| `docker-010` | H | 1+2 | _(B1)_ Exit code interpretation: 137 (SIGKILL = OOM) vs 139 (segfault) vs app-specific | _(B2)_ Common failure modes: bad entrypoint, missing env var, missing native deps in slim base |

### Linux (7 sources → 14 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `linux-001` | H | 1+2 | _(B1)_ Reading octal permission notation (e.g. 755) and what each digit grants | _(B2)_ Setuid / setgid / sticky bit semantics and the security implications |
| `linux-002` | H | 1+3 | _(B1)_ SIGTERM vs SIGKILL: catchable graceful vs uncatchable immediate | _(B3)_ Process states R/S/D/Z and what each tells you (especially D = uninterruptible sleep) |
| `linux-003` | H | 2+3 | _(B2)_ Unit file types: service vs timer vs target vs socket — when each is used | _(B3)_ journalctl filtering essentials: -u for unit, --since for time, -p for priority |
| `linux-004` | H | 1+2 | _(B1)_ Layered investigation: resolve (dig) → route (ip route) → port (ss) → packets (tcpdump) | _(B2)_ ss vs netstat: feature parity, performance, and why ss is the modern default |
| `linux-005` | H | 1+3 | _(B1)_ df reports filesystem free vs du reports directory usage — they can disagree | _(B3)_ Deleted-but-open-file gotcha: process holds inode; lsof +L1 / restart to release |
| `linux-006` | M | 1+2 | _(B1)_ journalctl (binary, indexed) vs grep on /var/log (text) for log workflow | _(B2)_ Timestamp filtering (--since / --until) and structured field filtering for fast triage |
| `linux-007` | M | 2+3 | _(B2)_ set -euo pipefail behaviour: exit on error, on unset var, on pipe failure | _(B3)_ When to abandon bash for Python: data structures, error handling, testability |

### Git (6 sources → 12 MCQs)

| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |
|---|---|---|---|---|
| `git-001` | H | 1+2 | _(B1)_ History preservation (merge) vs linear history (rebase) trade-off | _(B2)_ Why you never rebase a branch others have pulled (rewrites shared history) |
| `git-002` | M | 1+2 | _(B1)_ Required reviews and required status checks as the core protection mechanisms | _(B2)_ Force-push prevention and the admin bypass risk |
| `git-003` | M | 1+3 | _(B1)_ Clone (git-native, any remote) vs fork (GitHub feature, server-side copy) | _(B3)_ PR-from-fork workflow: upstream remote, sync, push to origin, open PR |
| `git-004` | M | 2+3 | _(B2)_ git bisect workflow as a binary search over commit history | _(B3)_ git blame shows the last-touching commit only — not full historical attribution |
| `git-005` | M | 1+3 | _(B1)_ Conflict marker format (<<<<<<< / ======= / >>>>>>>) and how to read it | _(B3)_ Strategies to avoid conflicts: small PRs, frequent rebase, clear ownership |
| `git-006` | M | 2+3 | _(B2)_ .gitignore is ignored for already-tracked files (need git rm --cached first) | _(B3)_ Secret-in-history recovery: git filter-repo / BFG and the rotate-the-secret rule |

## What I need from Stephen before Phase 2

Sign-off (or redlines) on:

1. **Domain/bank split** — does the 70/69/69 split with the priority spread above look balanced enough?

2. **Pair allocation** — any source whose two MCQs should NOT go in the bank pair shown?

3. **Concept angles** — any source where the two angles overlap too much, or miss the most testable concept?

4. **Lab number / location** — brief says `cloud-labs/project-XXX-interview-drill/` but the repo convention is `lab-NNN-kebab-name`. Last lab is 092 with a gap at 088-089. Confirm whether to use `lab-093` (next sequence head) or fill `lab-088`.

5. **Source URL** — `raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` returns 404. Should I keep using the local copy at `Interview Prep App/Interview-Prep-Combined.md`, or is the repo URL meant to be public?
