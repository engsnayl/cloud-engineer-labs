"""Two MCQ concept-angles per source. One-sentence outlines for Phase 1 review.

Each value is (mcq_1_angle, mcq_2_angle). MCQ 1 goes to the lower-numbered
bank, MCQ 2 to the higher (per allocation.json). Angles are deliberately
distinct facets of the source so the two MCQs don't trivially overlap.
"""

ANGLES = {
    # ---- AWS (28) ----
    "aws-001": (
        "Subnet placement rules: which tier sits in public vs private subnets, and why",
        "Tier-to-tier security group chaining as the enforcement layer between web/app/data",
    ),
    "aws-002": (
        "Route table with 0.0.0.0/0 to IGW as the actual public/private differentiator",
        "NAT Gateway vs Internet Gateway placement and direction of traffic",
    ),
    "aws-003": (
        "Stateful SG vs stateless NACL: return-traffic behaviour after an inbound allow",
        "Rule evaluation order and default deny vs default allow between the two controls",
    ),
    "aws-005": (
        "Multi-AZ synchronous standby vs read replica asynchronous lag and failover semantics",
        "Choosing read scaling vs HA for a given workload — common misuse of read replicas for HA",
    ),
    "aws-007": (
        "RTO/RPO trade-offs across Backup / Pilot Light / Warm Standby / Multi-Site Active",
        "Picking the right DR pattern under a stated cost vs availability constraint",
    ),
    "aws-008": (
        "S3 storage class fit: Standard vs IA vs Glacier Instant vs Glacier Deep Archive",
        "Lifecycle policy gotchas: minimum storage duration and retrieval cost charges",
    ),
    "aws-009": (
        "Block (EBS) vs file (EFS) vs file-protocol (FSx) selection by access pattern",
        "Single-attach vs multi-attach: EBS Multi-Attach caveats vs EFS shared access",
    ),
    "aws-010": (
        "Block Public Access vs bucket policy: which wins when they disagree",
        "Bucket policy vs IAM policy interaction for cross-account S3 access",
    ),
    "aws-012": (
        "ALB Layer 7 routing capabilities vs NLB Layer 4 use cases",
        "Picking ALB vs NLB vs GWLB for TLS termination, WebSocket, or low-latency UDP",
    ),
    "aws-013": (
        "What deregistration delay actually does to in-flight connections",
        "Impact of connection draining on rolling deploys and ASG scale-in events",
    ),
    "aws-014": (
        "Inbound vs outbound capability: IGW (both) vs NAT Gateway (outbound only)",
        "Cost and AZ-resilience trade-offs: NAT Gateway per-AZ vs single-AZ NAT instance",
    ),
    "aws-015": (
        "VPC Peering's non-transitive routing limit vs Transit Gateway hub-and-spoke",
        "PrivateLink as service-not-VPC exposure (one-way endpoint into a service)",
    ),
    "aws-016": (
        "Latency vs Geolocation vs Geoproximity routing — distinct decision inputs",
        "Failover routing policy and the health check requirement that makes it work",
    ),
    "aws-017": (
        "Gateway endpoint (S3, DynamoDB only) vs Interface endpoint (PrivateLink)",
        "VPC endpoints as NAT-cost avoidance and the DNS resolution behaviour they require",
    ),
    "aws-019": (
        "Instance family naming (M/C/R/G) and how to map workload profile to family",
        "Right-sizing methodology: CloudWatch metrics + Compute Optimizer recommendations",
    ),
    "aws-020": (
        "Target tracking vs step scaling: which fits steady demand vs spiky demand",
        "Cooldown periods and scale-in protection semantics during deployments",
    ),
    "aws-021": (
        "When Spot is appropriate: workload interruption tolerance and checkpointing",
        "RI vs Savings Plan: discount magnitude vs flexibility (instance family lock-in)",
    ),
    "aws-022": (
        "When Lambda is the wrong answer: 15-min limit, cold start, sustained workloads",
        "ECS vs EKS operational overhead — when EKS earns its complexity",
    ),
    "aws-024": (
        "First-action playbook: Cost Explorer + tagging analysis before architectural changes",
        "Pricing-model levers (RI/SP/Spot) vs architectural levers (right-size, S3 tier) by impact",
    ),
    "aws-026": (
        "When to use a role vs a user: workload identity and EC2/Lambda assume-role",
        "Long-term IAM user credentials vs temporary STS credentials and the rotation problem",
    ),
    "aws-027": (
        "Managed vs customer-managed vs inline: reusability and operational trade-offs",
        "Permissions boundary vs SCP vs identity policy — where each is enforced",
    ),
    "aws-028": (
        "Cross-account role assume: trust policy in target + sts:AssumeRole in source",
        "External ID as the confused deputy mitigation in third-party access patterns",
    ),
    "aws-029": (
        "Automatic rotation: Secrets Manager native integration with RDS vs Parameter Store manual",
        "Cost per secret/parameter vs feature parity — when Parameter Store is enough",
    ),
    "aws-030": (
        "Standard vs high-resolution metrics and custom metric cost per metric",
        "Composite alarms vs threshold alarms for noise reduction in incident channels",
    ),
    "aws-031": (
        "First commands to run on a 90% CPU EC2 instance (top/htop, vmstat, pidstat)",
        "Distinguishing symptom from cause: traffic spike vs runaway thread vs noisy neighbour",
    ),
    "aws-032": (
        "Where latency hides in a 3-tier app: DNS, LB, app, DB, downstream service",
        "Distributed tracing (X-Ray) vs metric-only investigation for slow requests",
    ),
    "aws-034": (
        "What actually happens during a Lambda cold start (init phase + package load)",
        "Provisioned Concurrency vs SnapStart vs runtime choice — distinct mitigations",
    ),
    "aws-035": (
        "REST vs HTTP API: feature parity, cost, and which to pick for a new build",
        "Lambda proxy integration vs HTTP_PROXY vs AWS service integration patterns",
    ),

    # ---- KUBERNETES (22) ----
    "k8s-001": (
        "What each abstraction owns: Deployment manages ReplicaSet manages Pods",
        "When you'd ever hand-create a ReplicaSet vs a Deployment in practice",
    ),
    "k8s-002": (
        "Pod phase transitions: Pending → Running → Succeeded/Failed and what each means",
        "Where pods get stuck: Pending = scheduling vs CrashLoopBackOff = container exit",
    ),
    "k8s-003": (
        "Liveness vs readiness vs startup probe: what each triggers when it fails",
        "Misconfigured liveness probe that restarts a slow-starting app on every boot",
    ),
    "k8s-004": (
        "Init container ordering and how it blocks main container start",
        "Native sidecar containers (1.28+): restartPolicy: Always init and lifecycle ordering",
    ),
    "k8s-005": (
        "CPU throttle (compressible) vs memory OOMKilled (incompressible) under limit pressure",
        "QoS class assignment (Guaranteed / Burstable / BestEffort) and eviction order",
    ),
    "k8s-010": (
        "ClusterIP vs NodePort vs LoadBalancer vs ExternalName exposure scope",
        "When to use Ingress instead of multiple LoadBalancer services",
    ),
    "k8s-011": (
        "Ingress object vs Ingress controller (you need both, controller is the implementation)",
        "Host-based vs path-based routing and where TLS termination happens",
    ),
    "k8s-012": (
        "Default-allow until a NetworkPolicy selects the pod, then default-deny within scope",
        "CNI requirement: VPC CNI native vs Calico/Cilium for NetworkPolicy support",
    ),
    "k8s-013": (
        "CoreDNS as the cluster resolver and service-name FQDN format (svc.ns.svc.cluster.local)",
        "Pod DNS resolution flow and ndots/search domains gotcha for cross-namespace lookups",
    ),
    "k8s-014": (
        "DNS-based discovery vs env-var injection (env vars are start-time-only)",
        "ExternalName services for integrating external endpoints into in-cluster DNS",
    ),
    "k8s-020": (
        "Workload type fit: Deployment vs StatefulSet vs DaemonSet vs Job by requirement",
        "StatefulSet specifics: stable network identity, ordered rollout, persistent volume claim per pod",
    ),
    "k8s-021": (
        "Taints/tolerations as exclusion vs nodeSelector/affinity as inclusion",
        "required vs preferred affinity and using anti-affinity for HA across nodes/AZs",
    ),
    "k8s-022": (
        "PDB blocks voluntary disruption only (node drain) — not pod crashes",
        "Pre-stop hook + terminationGracePeriodSeconds role in clean shutdown",
    ),
    "k8s-023": (
        "HPA (replica count) vs VPA (resource size) vs Cluster Autoscaler (node count) dimensions",
        "Karpenter just-in-time provisioning vs Cluster Autoscaler ASG-bound model",
    ),
    "k8s-030": (
        "Secrets are base64-encoded, not encrypted — and what KMS envelope encryption actually adds",
        "When to use ConfigMap vs Secret and the 1 MiB size limit on both",
    ),
    "k8s-031": (
        "External Secrets Operator vs Secrets Store CSI Driver: pull-on-mount vs sync-to-Secret",
        "IRSA wiring for a pod to fetch from AWS Secrets Manager without static credentials",
    ),
    "k8s-032": (
        "Role/RoleBinding vs ClusterRole/ClusterRoleBinding and which combinations are legal",
        "Cluster-scoped vs namespace-scoped permissions and least-privilege patterns",
    ),
    "k8s-040": (
        "EKS shared-responsibility split: AWS manages control plane, you manage workloads",
        "Managed node groups vs Fargate vs Karpenter — when each is the right compute choice",
    ),
    "k8s-041": (
        "IRSA mechanics: OIDC provider on cluster + projected service-account JWT token",
        "IRSA vs EKS Pod Identity: agent-based vs OIDC-based and migration considerations",
    ),
    "k8s-042": (
        "VPC CNI assigns real VPC IPs to pods, so pod density is ENI×IP-per-ENI bound",
        "Mitigations: prefix delegation (recommended) vs custom networking vs IPv6",
    ),
    "k8s-050": (
        "Pending = scheduler can't place (resources / affinity) vs ImagePullBackOff = registry/auth",
        "CrashLoopBackOff investigation order: previous-pod logs, exit code, then describe",
    ),
    "k8s-051": (
        "Where latency hides in a K8s service path: DNS, kube-proxy, CNI overhead, app, downstream",
        "Tooling fit: kubectl top vs describe vs exec — which to reach for first",
    ),

    # ---- CICD (18) ----
    "cicd-001": (
        "Continuous Delivery (deployable to prod) vs Continuous Deployment (automatic to prod)",
        "Where CI ends and CD begins: artifact promotion as the handoff",
    ),
    "cicd-002": (
        "Stage ordering: fail-fast linters and unit tests before slow integration tests",
        "Parallelisation strategy and the speed vs thoroughness trade-off in pipeline design",
    ),
    "cicd-003": (
        "Why long-lived feature branches break CI/CD (drift, merge-hell, stale tests)",
        "Feature flags as the mechanism that decouples deploy from release in trunk-based",
    ),
    "cicd-010": (
        "Workflow → job → step → runner hierarchy and where each piece of config lives",
        "GitHub-hosted vs self-hosted runners: cost, security, and isolation trade-offs",
    ),
    "cicd-011": (
        "Reusable workflows (separate workflow file, separate run) vs composite actions (inline)",
        "Picking reusable workflow vs composite action by need for secrets/contexts and reuse scope",
    ),
    "cicd-012": (
        "Matrix expansion semantics: cross-product of declared dimensions",
        "Cost-aware matrix design with include / exclude rules to prune wasteful combinations",
    ),
    "cicd-013": (
        "Cache key strategy: hashing lock files for stability and invalidation control",
        "Docker layer caching: BuildKit cache mounts and registry-backed cache for multi-runner",
    ),
    "cicd-014": (
        "Secret scoping: repo vs org vs environment, and the blast-radius implication",
        "Environment protection rules: required reviewers and wait timers as deploy gates",
    ),
    "cicd-020": (
        "Why OIDC beats static IAM access keys (no long-lived secret, audit trail per run)",
        "Trust policy sub-claim restrictions (branch, environment) to prevent token misuse",
    ),
    "cicd-021": (
        "kubectl apply vs Helm vs kustomize trade-offs in a deploy pipeline",
        "Push-based (kubectl from CI) vs pull-based (Argo CD / Flux GitOps) deployment models",
    ),
    "cicd-022": (
        "Task definition revisioning and how ECS rolling update progresses",
        "ECS rolling update vs CodeDeploy blue/green: when the latter earns its complexity",
    ),
    "cicd-030": (
        "Rolling vs blue-green vs canary: risk, cost, and rollback-speed trade-offs",
        "Feature flags as a complementary mechanism (release ≠ deploy)",
    ),
    "cicd-031": (
        "Expand-contract pattern: additive schema change first, app cutover, then contract",
        "Backwards-compatibility window: app must read old + new schema during deploy",
    ),
    "cicd-032": (
        "Automated rollback triggers: health-check failure thresholds vs error-rate alarms",
        "Why database changes resist rollback and the forward-fix bias in mature pipelines",
    ),
    "cicd-040": (
        "SAST vs DAST vs SCA vs container scanning — what class of issue each catches",
        "Where in the pipeline each scan runs (commit, build, pre-deploy, runtime)",
    ),
    "cicd-041": (
        "Quality gate semantics: new-code metrics vs whole-codebase metrics in PR gating",
        "Integration shape with GitHub Actions: pull-request decoration and gate enforcement",
    ),
    "cicd-050": (
        "Distinguishing flaky tests from real failures: re-run patterns and quarantine",
        "Common flake sources: timing, parallel shared state, network, container start delays",
    ),
    "cicd-051": (
        "Design priorities a pipeline owner balances: speed, signal, cost, security",
        "Trade-offs and lessons from a real pipeline (what you'd do differently next time)",
    ),

    # ---- TERRAFORM (13) ----
    "tf-001": (
        "Plan / apply / destroy lifecycle and what state contributes at each step",
        "Terraform vs CloudFormation / CDK trade-offs: multi-cloud, HCL ergonomics, drift",
    ),
    "tf-002": (
        "DynamoDB state locking is advisory and fail-fast (not a queue)",
        "Why remote state and why state files contain sensitive data (encrypt the bucket)",
    ),
    "tf-003": (
        "Module interface design: clear inputs / outputs / required-providers contract",
        "Module versioning and registry usage (semantic versions in source = ref=)",
    ),
    "tf-004": (
        "Variable precedence: CLI -var > -var-file > env TF_VAR_ > terraform.tfvars > defaults",
        "Locals (computed inside config) vs variables (user input) — when each is right",
    ),
    "tf-005": (
        "Workspaces caveat: single backend, similar configs only — not a prod isolation tool",
        "Separate-state per env vs workspaces vs Terragrunt-style DRY for env management",
    ),
    "tf-006": (
        "Why tfvars + .gitignore is risky: secrets still land in state files",
        "Data source pattern: fetch secrets at apply time from Secrets Manager / Vault",
    ),
    "tf-007": (
        "Why provisioners are an antipattern: state lies about provisioned-but-not-converged",
        "When local-exec / remote-exec is genuinely justified (and the better alternatives)",
    ),
    "tf-008": (
        "terraform refresh updates state to reality; apply changes reality to match config",
        "How drift gets introduced (out-of-band changes) and reconciliation options",
    ),
    "tf-009": (
        "Plan-on-PR / apply-on-merge pattern and the role of human approval",
        "State-lock contention in CI: parallel runs, cancelled apply, and orphan locks",
    ),
    "tf-010": (
        "Provisioning live infra (Terraform) vs baking machine images (Packer)",
        "Golden-image workflow: Packer builds AMI → Terraform consumes via data source",
    ),
    "tf-011": (
        "Index-addressed (count) vs key-addressed (for_each) resource stability",
        "The classic count problem: removing a middle item recreates all subsequent resources",
    ),
    "tf-012": (
        "moved block (TF 1.1+) for in-config renames without destroy/create",
        "terraform state mv vs import: when each applies during refactors",
    ),
    "tf-013": (
        "Common investigation steps: plan inspection, TF_LOG, state file diff",
        "Drift vs config bug vs provider bug — diagnosis path for ambiguous errors",
    ),

    # ---- DOCKER (10) ----
    "docker-001": (
        "Kernel-shared (containers, namespaces+cgroups) vs hardware-virtualised (VMs) isolation",
        "Resource overhead and start-time differences and where each fits",
    ),
    "docker-002": (
        "Layer order for cache reuse: copy lock files and install deps before copying source",
        "Non-root USER + minimal base image + COPY --chown for least-privilege containers",
    ),
    "docker-003": (
        "Build vs runtime stage separation so build toolchain doesn't ship in the final image",
        "Multi-stage as a build-time secret containment pattern (secrets stay in earlier stages)",
    ),
    "docker-004": (
        "Alpine vs distroless vs full OS base: trade-offs in glibc compatibility and debuggability",
        ".dockerignore + dependency pruning + single-RUN apt-get to keep layers small",
    ),
    "docker-005": (
        "Cache invalidation rule: any change in a COPY busts that layer and every layer after",
        "BuildKit improvements: cache mounts, parallel stage execution, secret mounts",
    ),
    "docker-006": (
        "Bridge vs host vs none vs custom network — semantics of each",
        "Container-name DNS resolution on user-defined networks (not default bridge)",
    ),
    "docker-007": (
        "Bind mounts (host-path coupled) vs named volumes (portable across hosts)",
        "tmpfs use case: in-memory secrets / ephemeral scratch space",
    ),
    "docker-008": (
        "Compose scope: dev and single-host orchestration — not a Kubernetes replacement",
        "Compose service dependencies (depends_on, healthcheck) and default network behaviour",
    ),
    "docker-009": (
        "ECR auth via aws ecr get-login-password — short-lived token, must re-auth",
        "Lifecycle policies for image pruning and tag immutability for reproducible deploys",
    ),
    "docker-010": (
        "Exit code interpretation: 137 (SIGKILL = OOM) vs 139 (segfault) vs app-specific",
        "Common failure modes: bad entrypoint, missing env var, missing native deps in slim base",
    ),

    # ---- LINUX (7) ----
    "linux-001": (
        "Reading octal permission notation (e.g. 755) and what each digit grants",
        "Setuid / setgid / sticky bit semantics and the security implications",
    ),
    "linux-002": (
        "SIGTERM vs SIGKILL: catchable graceful vs uncatchable immediate",
        "Process states R/S/D/Z and what each tells you (especially D = uninterruptible sleep)",
    ),
    "linux-003": (
        "Unit file types: service vs timer vs target vs socket — when each is used",
        "journalctl filtering essentials: -u for unit, --since for time, -p for priority",
    ),
    "linux-004": (
        "Layered investigation: resolve (dig) → route (ip route) → port (ss) → packets (tcpdump)",
        "ss vs netstat: feature parity, performance, and why ss is the modern default",
    ),
    "linux-005": (
        "df reports filesystem free vs du reports directory usage — they can disagree",
        "Deleted-but-open-file gotcha: process holds inode; lsof +L1 / restart to release",
    ),
    "linux-006": (
        "journalctl (binary, indexed) vs grep on /var/log (text) for log workflow",
        "Timestamp filtering (--since / --until) and structured field filtering for fast triage",
    ),
    "linux-007": (
        "set -euo pipefail behaviour: exit on error, on unset var, on pipe failure",
        "When to abandon bash for Python: data structures, error handling, testability",
    ),

    # ---- GIT (6) ----
    "git-001": (
        "History preservation (merge) vs linear history (rebase) trade-off",
        "Why you never rebase a branch others have pulled (rewrites shared history)",
    ),
    "git-002": (
        "Required reviews and required status checks as the core protection mechanisms",
        "Force-push prevention and the admin bypass risk",
    ),
    "git-003": (
        "Clone (git-native, any remote) vs fork (GitHub feature, server-side copy)",
        "PR-from-fork workflow: upstream remote, sync, push to origin, open PR",
    ),
    "git-004": (
        "git bisect workflow as a binary search over commit history",
        "git blame shows the last-touching commit only — not full historical attribution",
    ),
    "git-005": (
        "Conflict marker format (<<<<<<< / ======= / >>>>>>>) and how to read it",
        "Strategies to avoid conflicts: small PRs, frequent rebase, clear ownership",
    ),
    "git-006": (
        ".gitignore is ignored for already-tracked files (need git rm --cached first)",
        "Secret-in-history recovery: git filter-repo / BFG and the rotate-the-secret rule",
    ),
}
