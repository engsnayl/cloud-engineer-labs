# Multi-Tier Application: Build, Deploy, and Monitor

A production-ready three-tier web application with Terraform infrastructure, Kubernetes deployment, CI/CD pipeline, and Prometheus/Grafana monitoring.

---

## Architecture

```
                                    AWS (eu-west-2)
 ┌─────────────────────────────────────────────────────────────────────┐
 │  VPC 10.0.0.0/16                                                    │
 │  ┌──────────────────────────┐  ┌──────────────────────────┐        │
 │  │  Public Subnet (AZ-a)    │  │  Public Subnet (AZ-b)    │        │
 │  │  10.0.1.0/24             │  │  10.0.2.0/24             │        │
 │  └──────────────────────────┘  └──────────────────────────┘        │
 │  ┌──────────────────────────┐  ┌──────────────────────────┐        │
 │  │  Private Subnet (AZ-a)   │  │  Private Subnet (AZ-b)   │        │
 │  │  10.0.10.0/24            │  │  10.0.20.0/24            │        │
 │  └──────────────────────────┘  └──────────────────────────┘        │
 │                                                                     │
 │  ┌──────────────────────────────────────────────┐                  │
 │  │  ECR: frontend-repo  |  ECR: backend-repo    │                  │
 │  └──────────────────────────────────────────────┘                  │
 └─────────────────────────────────────────────────────────────────────┘
          │                                         ▲
          │ pull images                             │ push images
          ▼                                         │
 ┌─────────────────────────────────────────────────────────────────────┐
 │  GitHub Actions CI/CD                                               │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐       │
 │  │  Build   │─▶│   Test   │─▶│ Push ECR │─▶│ Deploy K8s   │       │
 │  └──────────┘  └──────────┘  └──────────┘  └──────────────┘       │
 └─────────────────────────────────────────────────────────────────────┘
          │
          │ kubectl apply
          ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │  Kubernetes Cluster (k3s on Raspberry Pi 5)                         │
 │  Namespace: multi-tier-app                                          │
 │                                                                     │
 │  ┌─────────────────────────────────────────────────────────┐       │
 │  │                     Ingress (Traefik)                    │       │
 │  │              /  ──▶  frontend    /api  ──▶  backend      │       │
 │  └─────────────────────────────────────────────────────────┘       │
 │                                                                     │
 │  ┌───────────────┐  ┌───────────────┐  ┌────────────────────┐      │
 │  │   Frontend    │  │    Backend    │  │    PostgreSQL      │      │
 │  │   nginx       │  │    Flask      │  │    StatefulSet     │      │
 │  │   2 replicas  │  │   2 replicas  │  │    1 replica + PVC │      │
 │  │   port 80     │  │   port 5000   │  │    port 5432       │      │
 │  └───────────────┘  └───────┬───────┘  └────────────────────┘      │
 │                              │ NetworkPolicy: only backend ──▶ DB  │
 │                              │                                      │
 │  ┌───────────────────────────▼──────────────────────────────┐      │
 │  │  Monitoring: Prometheus (scrape /metrics) ──▶ Grafana    │      │
 │  └──────────────────────────────────────────────────────────┘      │
 └─────────────────────────────────────────────────────────────────────┘
```

---

## Technology Choices

| Component | Technology | Why |
|-----------|-----------|-----|
| Frontend | nginx:alpine | Lightweight (~40MB), proven reverse proxy, serves static files efficiently |
| Backend | Python 3.11 + Flask | Simple to write, widely understood, excellent PostgreSQL support via psycopg2 |
| Database | PostgreSQL 15 | Production-grade RDBMS, official image with init script support |
| Container runtime | Docker + k3s containerd | Docker for building, k3s containerd for running in cluster |
| Orchestration | Kubernetes (k3s) | Lightweight K8s distribution ideal for ARM64/Raspberry Pi |
| Infrastructure | Terraform | Declarative, modular, state-tracked infrastructure as code |
| CI/CD | GitHub Actions | Free for public repos, native Docker/ECR integration |
| Container registry | AWS ECR | Private registry, IAM-integrated, lifecycle policies |
| Monitoring | Prometheus + Grafana | Industry standard for Kubernetes observability |
| Ingress | Traefik (k3s built-in) | Zero-config Ingress Controller bundled with k3s |

---

## Prerequisites

### Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | v29.2.1+ | Build container images |
| kubectl | v1.34+ | Interact with Kubernetes cluster |
| k3s | v1.34.4+ | Lightweight Kubernetes (on Raspberry Pi) |
| Terraform | v1.5+ | Provision AWS infrastructure |
| Helm | v3.12+ | Install Prometheus/Grafana stack |
| git | v2.40+ | Version control |
| curl | any | Test API endpoints |

### AWS Account Setup

1. Create an IAM user with permissions for VPC, ECR, S3, and DynamoDB
2. Configure AWS CLI: `aws configure` with access key, secret key, and region `eu-west-2`
3. Create an S3 bucket for Terraform state (e.g., `my-project-tf-state`)
4. Create a DynamoDB table for state locking (name: `terraform-locks`, partition key: `LockID`)

### GitHub Secrets (for CI/CD)

Configure these in your GitHub repository under Settings > Secrets and variables > Actions:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | `eu-west-2` |
| `KUBE_CONFIG` | Base64-encoded kubeconfig for your cluster |

---

## Quick Start -- Local (Docker Compose)

The fastest way to see the application running. No Kubernetes or AWS required.

```bash
cd solution

# Build and start all three tiers
docker-compose up --build -d

# Verify everything is running
docker-compose ps

# Test the API
curl http://localhost/api/health
# Expected: {"status": "healthy", "database": "connected"}

curl http://localhost/api/data
# Expected: {"items": [...three seed items...]}

# Open in browser
# http://localhost

# Stop and clean up
docker-compose down -v
```

Docker Compose starts PostgreSQL first (with a health check), then the backend (which waits for the database), then the frontend. The frontend is mapped to port 80 on your machine.

---

## Quick Start -- Kubernetes (Pi / k3s)

Deploy to your Raspberry Pi k3s cluster.

### Step 1: Build and import images

```bash
cd solution

# Build both images
docker build -t backend:latest docker/backend/
docker build -t frontend:latest docker/frontend/

# Import into k3s (k3s uses containerd, not Docker)
docker save backend:latest | sudo k3s ctr images import -
docker save frontend:latest | sudo k3s ctr images import -
```

### Step 2: Deploy in dependency order

```bash
# Namespace
kubectl apply -f k8s/namespace.yaml

# Database (deploy first -- backend depends on it)
kubectl apply -f k8s/database-secret.yaml
kubectl apply -f k8s/database-init-configmap.yaml
kubectl apply -f k8s/database-pvc.yaml
kubectl apply -f k8s/database-statefulset.yaml
kubectl apply -f k8s/database-service.yaml
kubectl wait --for=condition=ready pod/postgres-0 -n multi-tier-app --timeout=60s

# Backend
kubectl apply -f k8s/backend-configmap.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl rollout status deployment/backend -n multi-tier-app --timeout=60s

# Frontend
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl rollout status deployment/frontend -n multi-tier-app --timeout=60s

# Networking
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/network-policy.yaml
```

### Step 3: Access the application

```bash
# From the Pi itself
curl http://localhost/api/health

# From any device on the same network
# http://<your-pi-ip>
hostname -I    # Find your Pi's IP
```

---

## Quick Start -- AWS Infrastructure

Provision the AWS networking and ECR resources.

```bash
cd solution/terraform

# Initialise Terraform (downloads providers, initialises backend)
terraform init

# Check formatting
terraform fmt -check

# Validate configuration
terraform validate

# Preview what will be created
terraform plan

# Create the infrastructure (type "yes" when prompted)
terraform apply

# View outputs (VPC ID, ECR URLs, etc.)
terraform output
```

> **WARNING:** `terraform apply` creates real AWS resources that cost money. Run `terraform destroy` when you are done.

---

## CI/CD Pipeline

The GitHub Actions workflow at `.github/workflows/deploy.yml` runs on every push to `main`.

| Stage | What It Does | Trigger Condition |
|-------|-------------|-------------------|
| **Build** | Builds frontend and backend Docker images | Always |
| **Test** | Runs backend tests, lints Dockerfiles with hadolint | Always |
| **Push** | Authenticates to ECR, tags with git SHA, pushes images | Tests pass |
| **Deploy** | Runs `kubectl set image` to update Deployments | Push succeeds, main branch only |

Images are tagged with the git commit SHA (`abc123def`) rather than `latest`. This ensures every deployment is traceable to a specific commit and enables instant rollback by redeploying a previous SHA.

---

## Monitoring

### Install Prometheus and Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### Access Grafana

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Open `http://localhost:3000` -- default credentials: `admin` / `prom-operator`.

### Import the Dashboard

1. In Grafana, go to Dashboards > Import
2. Upload `solution/monitoring/grafana-dashboard.json`
3. Select the Prometheus datasource
4. The dashboard shows: request rate, health endpoint status, app version, and pod count

### Verify Prometheus Scraping

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open `http://localhost:9090/targets` -- the backend pods should appear as active targets.

---

## Project Structure

```
solution/
├── terraform/                          # AWS infrastructure as code
│   ├── main.tf                         # Root module composing child modules
│   ├── variables.tf                    # Input variables (region, project, env)
│   ├── outputs.tf                      # Exported values (VPC ID, ECR URLs)
│   ├── providers.tf                    # AWS provider configuration
│   ├── backend.tf                      # S3 remote state configuration
│   └── modules/
│       ├── networking/                 # VPC, subnets, IGW, route tables
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── security/                   # Security groups per tier
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── ecr/                        # Container image repositories
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── docker/
│   ├── frontend/
│   │   ├── Dockerfile                  # nginx:alpine with custom config
│   │   ├── .dockerignore               # Exclude .git, *.md from build
│   │   ├── nginx.conf                  # Static files + /api/ reverse proxy
│   │   └── index.html                  # Single-page frontend app
│   └── backend/
│       ├── Dockerfile                  # python:3.11-slim with Flask
│       ├── .dockerignore               # Exclude __pycache__, .git, *.pyc
│       └── app.py                      # Flask API: /api/health, /api/data, /metrics
├── docker-compose.yml                  # Local dev: all 3 tiers with one command
├── k8s/
│   ├── namespace.yaml                  # multi-tier-app namespace
│   ├── database-secret.yaml            # PostgreSQL credentials (base64)
│   ├── database-init-configmap.yaml    # SQL init script (CREATE TABLE, INSERT)
│   ├── database-pvc.yaml              # 1Gi persistent storage
│   ├── database-statefulset.yaml       # PostgreSQL StatefulSet (1 replica)
│   ├── database-service.yaml           # Headless Service for stable DNS
│   ├── backend-configmap.yaml          # Non-sensitive DB connection config
│   ├── backend-deployment.yaml         # Flask Deployment (2 replicas, probes)
│   ├── backend-service.yaml            # ClusterIP Service on port 5000
│   ├── frontend-deployment.yaml        # nginx Deployment (2 replicas)
│   ├── frontend-service.yaml           # ClusterIP Service on port 80
│   ├── ingress.yaml                    # Path-based routing (/ and /api)
│   └── network-policy.yaml             # DB access restricted to backend only
├── .github/
│   └── workflows/
│       └── deploy.yml                  # CI/CD: build, test, push ECR, deploy
├── monitoring/
│   ├── prometheus-config.yaml          # Scrape config for backend metrics
│   └── grafana-dashboard.json          # Importable dashboard definition
└── README.md                           # This file
```

---

## Production Considerations

| Concern | Learning Version | Production Version |
|---------|-----------------|-------------------|
| **Database** | PostgreSQL StatefulSet in K8s | AWS RDS/Aurora with automated backups, Multi-AZ failover |
| **TLS/HTTPS** | Plain HTTP | cert-manager + Let's Encrypt, or ACM certificates on ALB |
| **Scaling** | Fixed 2 replicas | Horizontal Pod Autoscaler (HPA) based on CPU/memory/custom metrics |
| **Secrets** | K8s Secrets (base64 encoded) | External Secrets Operator + AWS Secrets Manager or HashiCorp Vault |
| **Logging** | Container stdout | Fluent Bit DaemonSet forwarding to CloudWatch Logs or Elasticsearch |
| **CI/CD runners** | GitHub-hosted runners | Self-hosted runners in private subnet for speed and security |
| **Image signing** | No verification | cosign/Notary image signing with admission controller enforcement |
| **Environments** | Single namespace | Separate namespaces/clusters for dev, staging, prod with promotion gates |
| **DNS** | localhost / Pi IP | Route 53 with custom domain, health checks, weighted routing |
| **Service mesh** | NetworkPolicy only | Istio/Linkerd with mTLS, traffic policies, circuit breakers |
| **Backup** | No backup strategy | Automated pg_dump to S3, or RDS automated snapshots with retention |
| **Resource tuning** | Estimated limits | Load-tested and right-sized based on actual traffic patterns |

---

## Cleanup

> **IMPORTANT: AWS resources cost money. Always destroy infrastructure when you are done.**

### 1. Terraform (AWS)

```bash
cd solution/terraform
terraform destroy
# Type "yes" when prompted
# Verify in AWS Console that VPC, ECR repos, and security groups are gone
```

### 2. Kubernetes

```bash
kubectl delete namespace multi-tier-app
# This removes ALL resources: pods, services, deployments, secrets, PVCs, ingress, etc.
```

### 3. Docker

```bash
docker-compose down -v
docker rmi frontend:latest backend:latest
docker system prune -f
```

### 4. Monitoring (if installed)

```bash
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```
