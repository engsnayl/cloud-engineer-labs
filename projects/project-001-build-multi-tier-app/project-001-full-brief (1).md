# Project 001 — Full Capstone Brief for Claude Code

## Context

This is the capstone project for Stephen's cloud-engineer-labs curriculum (87+ hands-on labs across Linux, Docker, Kubernetes, Terraform/AWS, CI/CD, and Monitoring). The project must showcase **every major track** in the curriculum — not just Kubernetes. The current build only covers the Docker + K8s slice. This brief defines the full scope.

The purpose of this project is twofold:
1. **Interview narrative** — Stephen needs to be able to say "I designed, provisioned, containerised, deployed, pipelined, and monitored a full three-tier application end-to-end" and walk through every layer.
2. **Portfolio piece** — the GitHub repo itself is a deliverable. An interviewer browsing it should see Terraform modules, K8s manifests, a CI/CD pipeline, monitoring config, and clear documentation.

## Environment

- **Local:** Raspberry Pi 5 Model B, 4GB RAM, ARM64/aarch64, running K3s (v1.34.4+k3s1, single-node)
- **Cloud:** AWS account (IAM user StephenNaylor, eu-west-1 Ireland region)
- **Tools:** Terraform 1.10.5, AWS CLI 2.34.5, Docker, kubectl, K3s
- **Repo:** `github.com/engsnayl/cloud-engineer-labs` — project lives at `projects/project-001-build-multi-tier-app/`
- **Editor workflow:** Edit files on GitHub web → `git pull` to Pi (not edit-locally-then-push)
- **ARM64 constraint:** All Docker images must work on aarch64. `act` (local GitHub Actions runner) has ARM64 compatibility issues — avoid it.
- **Port 80 conflict:** K3s Traefik intercepts port 80. Use 8080:80 mappings where needed.
- **K3s CNI:** Flannel — does NOT enforce NetworkPolicies. NetworkPolicy manifests should still be included for correctness/interview value, but document that live enforcement requires Calico/Cilium.

## What the Project Must Cover

### Track 1: Terraform / AWS Infrastructure

The project must include a Terraform configuration that provisions real AWS resources. This is the biggest gap in the current build.

**Minimum AWS resources to provision:**
- VPC with public and private subnets (at least 2 AZs)
- Internet Gateway + NAT Gateway
- Security Groups (least-privilege: frontend SG allows 80/443 inbound, backend SG allows traffic only from frontend SG, database SG allows 5432 only from backend SG)
- An ECR repository for each Docker image (frontend, backend) — so the CI/CD pipeline has somewhere to push images
- (Optional but high interview value) An S3 bucket for Terraform remote state + DynamoDB table for state locking

**Terraform standards:**
- Modular structure: `terraform/modules/vpc/`, `terraform/modules/ecr/`, etc. or a single module with clear variable separation
- Variables file with sensible defaults and descriptions
- Outputs file exposing key values (VPC ID, subnet IDs, ECR repo URLs, security group IDs)
- `terraform.tfvars.example` (not the real one) committed to the repo
- Backend config for remote state (even if Stephen uses local state during initial build, the config should be there and documented)
- **Every solution file and README must include a prominent `terraform destroy` reminder**

**What this proves in an interview:** "I can provision production-grade networking and container infrastructure on AWS using Terraform, with proper modularisation and state management."

### Track 2: Docker / Containerisation

This is partially done in the current build. Keep the three-tier app:
- **Frontend:** nginx serving static HTML + reverse proxying `/api/` to backend
- **Backend:** Python Flask API with `/api/health`, `/api/data`, `/metrics`
- **Database:** PostgreSQL with persistent storage, init script, credentials via Secret

**Additional requirements:**
- Multi-stage Dockerfiles where appropriate (backend doesn't need it given it's tiny, but document why)
- `.dockerignore` files
- Images must build on ARM64 (Pi) — verify base images support `linux/arm64`
- A `docker-compose.yml` at the project root for local development (spin up all three tiers locally without K8s) — this is a common interview question: "how do developers run this locally?"

**What this proves in an interview:** "I understand containerisation, image optimisation, and the difference between local dev (compose) and production (K8s) workflows."

### Track 3: Kubernetes Manifests

The current build covers this well. Keep everything from the existing solution but ensure:
- Namespace isolation (`multi-tier-app`)
- StatefulSet for PostgreSQL with PVC and init ConfigMap
- Deployments for frontend (2 replicas) and backend (2 replicas)
- Services (headless for Postgres, ClusterIP for frontend/backend)
- ConfigMap for non-sensitive config, Secret for credentials
- Readiness and liveness probes on all tiers
- Ingress for path-based routing
- NetworkPolicy restricting DB access to backend only (note Flannel limitation)
- Resource requests and limits on all containers
- Prometheus annotations on the backend pods

**Additional requirements:**
- A `kustomization.yaml` or a clear `kubectl apply` ordering script — interviewers like to see you've thought about deployment ordering
- Comments in manifests explaining non-obvious choices (e.g., why StatefulSet, why headless Service, why subPath on PVC)

**What this proves in an interview:** "I can design and deploy a production-grade Kubernetes architecture with proper resource management, health checking, security controls, and persistent storage."

### Track 4: CI/CD Pipeline

This is completely missing from the current build and was explicitly flagged as critical for interview readiness.

**Build a GitHub Actions pipeline (`.github/workflows/deploy.yml`) that does:**

1. **Build stage:** Build Docker images for frontend and backend
2. **Test stage:** Run a basic health check or unit test (even a simple `curl` against a container-started app counts)
3. **Push stage:** Tag and push images to ECR (use the ECR repos provisioned by Terraform)
4. **Deploy stage:** Update the K8s manifests with the new image tag and apply them (this can be a `kubectl set image` command or a manifest patch)

**Pipeline standards:**
- Secrets (AWS credentials, kubeconfig) stored in GitHub Actions secrets — document what needs to be set up
- Pipeline triggers on push to `main` branch
- Clear job separation (build → test → push → deploy) so the pipeline is readable
- A manual approval gate or environment protection rule before the deploy stage (even if not enforced, include the config and document it)

**Note on ARM64 and `act`:** Do NOT use `act` for local testing — it has ARM64 compatibility issues on the Pi. The pipeline runs on GitHub's hosted runners (x86_64). If images need to run on the Pi (ARM64), either use multi-arch builds (`docker buildx`) or document that the pipeline builds x86 images for cloud deployment while local Pi builds use native ARM64.

**What this proves in an interview:** "I've built a complete CI/CD pipeline — build, test, push, deploy — with proper secret management and deployment gates. I can walk you through every stage."

### Track 5: Monitoring and Observability

This is mostly missing from the current build (only Prometheus annotations exist).

**Add:**
- A Prometheus scrape config (ConfigMap or ServiceMonitor) that targets the backend's `/metrics` endpoint
- A basic Grafana dashboard JSON file (even a single dashboard with request count and health status panels)
- The backend `/metrics` endpoint already exists — make sure it returns meaningful Prometheus-format metrics
- Document how to access Prometheus and Grafana via `kubectl port-forward`

**Stretch (if time allows):**
- AlertManager config with a basic alert rule (e.g., alert if backend health check fails for > 1 minute)
- Log aggregation note (even just documenting "in production, add Fluent Bit DaemonSet forwarding to CloudWatch/ELK")

**What this proves in an interview:** "I understand observability — metrics collection, dashboarding, and alerting. I've wired Prometheus into my application and built dashboards to monitor it."

### Track 6: Documentation (README / Architecture)

The current solution has a good README. Expand it to cover ALL tracks:

**README must include:**
- Architecture diagram (ASCII is fine) showing: AWS infrastructure (VPC, subnets, ECR) → CI/CD pipeline → K8s cluster (all tiers) → Monitoring stack
- Technology choices table with rationale for each component
- **Prerequisites section:** What needs to be installed, what AWS resources need to exist, what secrets need to be configured
- **Quick start guide:** Step-by-step from `git clone` to working application (both local docker-compose AND K8s deployment)
- **CI/CD pipeline description:** What each stage does, what triggers it, where secrets are configured
- **Monitoring section:** How to access Prometheus/Grafana, what metrics are available
- **Production considerations:** What would change for a real production deployment (managed DB, TLS, HPA, proper secrets management, etc.)
- **Cleanup section:** `terraform destroy` + `kubectl delete namespace` + any other teardown steps. Prominent and unmissable.

## Directory Structure

```
projects/project-001-build-multi-tier-app/
├── CHALLENGE.md                    # The brief (what the student sees)
├── SOLUTION.md                     # Full annotated walkthrough
├── docker-compose.yml              # Local dev: spin up all 3 tiers
├── docker/
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── .dockerignore
│   │   ├── nginx.conf
│   │   └── index.html
│   └── backend/
│       ├── Dockerfile
│       ├── .dockerignore
│       ├── app.py
│       └── requirements.txt
├── terraform/
│   ├── main.tf                     # Root module
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example    # Example values (real .tfvars is gitignored)
│   ├── backend.tf                  # Remote state config (S3 + DynamoDB)
│   └── modules/
│       ├── vpc/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── ecr/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── k8s/
│   ├── namespace.yaml
│   ├── database-secret.yaml
│   ├── database-init-configmap.yaml
│   ├── database-pvc.yaml
│   ├── database-statefulset.yaml
│   ├── database-service.yaml
│   ├── backend-configmap.yaml
│   ├── backend-deployment.yaml
│   ├── backend-service.yaml
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml
│   ├── ingress.yaml
│   └── network-policy.yaml
├── .github/
│   └── workflows/
│       └── deploy.yml              # CI/CD pipeline
├── monitoring/
│   ├── prometheus-config.yaml      # Scrape config
│   └── grafana-dashboard.json      # Dashboard definition
├── validate.sh                     # Validation script
└── README.md                       # Full architecture documentation
```

## SOLUTION.md Standards

The solution file must follow the established format from all other labs:

1. **Plain-English TLDR** at the top — what this project builds, what skills it demonstrates, and the high-level approach
2. **Step-by-step investigative learning pathway** — written as a build guide where each step explains: what we're building → why this component exists → what decisions we're making → what the code does → how to verify it works before moving on
3. **Command breakdown tables** for every non-obvious command (each flag/component explained separately)
4. **Bottom-up build order:** Terraform infrastructure → Database → Backend → Frontend → Networking → CI/CD → Monitoring → Documentation
5. **`vi` preferred** for file edits over complex one-liners
6. **"Project vs Real Life" section** — what would differ in a production environment
7. **Key Concepts Learned** — summary of every skill demonstrated
8. **Cleanup section** — `terraform destroy`, `kubectl delete namespace`, any other teardown. Prominent and unmissable.
9. **No bug hint comments** in any files — this is a build project, not a troubleshoot, but the principle still applies: no signposting or scaffolding comments

## CHALLENGE.md Standards

The challenge file is what Stephen sees before starting. It should:

1. **Set the scene** — "You've been asked to build and deploy a production-ready three-tier application, provision its cloud infrastructure, build a CI/CD pipeline, and add monitoring."
2. **List requirements by track** — Terraform, Docker, K8s, CI/CD, Monitoring, Documentation
3. **Specify acceptance criteria** — what does "done" look like for each track?
4. **NOT give away the solution** — no specific resource names, no file contents, no architectural decisions. Just requirements.
5. **Include a skills checklist** — at the end, a checklist of every skill this project tests (e.g., "☐ Terraform modules", "☐ Kubernetes StatefulSets", "☐ GitHub Actions secrets management")

## Validation Script

`validate.sh` should check:
- Terraform: `terraform validate` passes, expected resources exist in state
- Docker: Images build successfully
- K8s: All pods running, services responding, health checks passing
- CI/CD: `.github/workflows/deploy.yml` exists and contains expected stages
- Monitoring: Prometheus config exists, Grafana dashboard JSON is valid
- Documentation: README.md exists and contains required sections

## What NOT to Include

- No Helm charts — that's a separate lab (039). Keep manifests as plain YAML.
- No ArgoCD — that's a separate lab (046). Keep deployment as `kubectl apply`.
- No EKS/managed K8s — the project runs on K3s on the Pi. The Terraform provisions supporting infrastructure (VPC, ECR, networking), not the cluster itself.
- No service mesh (Istio/Linkerd) — out of scope for mid-level.
- No multi-environment configs (dev/staging/prod) — one environment is sufficient for the capstone.

## Summary

When complete, Stephen should be able to say in an interview:

> "I built a three-tier web application from scratch — an nginx frontend, Flask API backend, and PostgreSQL database. I containerised all tiers with Docker, wrote a docker-compose for local development, and deployed to Kubernetes with StatefulSets, Deployments, Services, Ingress, and NetworkPolicies. I provisioned the cloud infrastructure with Terraform — VPC, subnets, security groups, and ECR repositories — using a modular structure with remote state. I built a CI/CD pipeline in GitHub Actions that builds, tests, pushes to ECR, and deploys to the cluster. And I added Prometheus metrics collection and a Grafana dashboard for observability. The whole thing is documented with architecture diagrams and production considerations."

That's the capstone narrative. Every track in the curriculum, demonstrated in one cohesive project.
