# Cloud Engineer Labs

A self-directed lab framework for practising real-world cloud engineering and Linux troubleshooting skills. Each lab simulates a realistic broken or incomplete environment that you must diagnose and fix — just like you would on the job.

**74 labs + 1 capstone project** across seven categories: Linux, Docker, Kubernetes, Terraform/AWS, CI/CD, Monitoring, and Projects.

## Structure

```
cloud-engineer-labs/
├── linux-labs/          # Linux + Docker troubleshooting labs (27 labs)
│   ├── lab-001 … lab-018   (Linux)
│   └── lab-019 … lab-024, lab-035 … lab-037   (Docker)
├── k8s-labs/            # Kubernetes troubleshooting labs (12 labs)
│   └── lab-025 … lab-036
├── cloud-labs/          # Terraform / AWS infrastructure labs (22 labs)
│   └── lab-001 … lab-022
├── cicd-labs/           # CI/CD pipeline labs (5 labs)
│   └── lab-040 … lab-044
├── monitoring-labs/     # Monitoring & incident response labs (7 labs)
│   └── lab-050 … lab-056
├── projects/            # Capstone projects (1 project)
│   └── project-001
├── tools/
│   └── labrunner.sh     # CLI runner
├── CREATING_LABS.md
└── README.md
```

## Lab Catalogue

### Linux Troubleshooting (18 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 001 | Web Server Down — Nginx Won't Start | Intermediate | 10-15 min |
| 002 | DNS Resolution Failing | Intermediate | 10-15 min |
| 003 | Disk Full — App Logging Consumed All Storage | Beginner-Intermediate | 10-15 min |
| 004 | SSH Access Denied — Key Auth Failing | Intermediate | 10-15 min |
| 005 | Runaway Process Consuming CPU | Intermediate | 8-12 min |
| 006 | Backup Job Not Running — Cron Misconfigured | Intermediate | 10-15 min |
| 007 | Firewall Rules Blocking Traffic | Advanced | 15-20 min |
| 008 | User and Group Permissions Broken | Intermediate | 10-15 min |
| 009 | Systemd Service Crash Loop | Advanced | 15-20 min |
| 010 | Log Rotation Not Working | Intermediate | 10-15 min |
| 011 | Filesystem Mount Failed | Advanced | 15-20 min |
| 012 | OOM Killer — Memory Pressure and Swap | Advanced | 15-20 min |
| 013 | TCP Connection Timeout Debugging | Intermediate | 10-15 min |
| 014 | HTTPS Broken — SSL Certificate Issues | Advanced | 15-20 min |
| 015 | Service Won't Start — Port Conflict | Beginner | 8-10 min |
| 016 | Load Balancer Not Distributing — Reverse Proxy Misconfigured | Advanced | 15-20 min |
| 017 | API Requests Failing — Proxy Headers and CORS Issues | Advanced | 15-20 min |
| 018 | Mystery Traffic — Packet Capture Analysis | Advanced | 15-20 min |

### Docker Troubleshooting (9 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 019 | Container Won't Start | Intermediate | 10-15 min |
| 020 | Containers Can't Talk — Network Issues | Intermediate | 12-15 min |
| 021 | Data Missing — Volume Mount Problems | Intermediate | 10-15 min |
| 022 | Build Broken — Dockerfile Debugging | Intermediate | 10-15 min |
| 023 | Compose Chaos — Multi-Container App Broken | Advanced | 15-20 min |
| 024 | Container Keeps Dying — OOM Kills | Advanced | 12-15 min |
| 035 | Image Too Large — Multi-Stage Build Optimisation | Intermediate | 12-15 min |
| 036 | Where Are The Logs — Container Logging Debugging | Intermediate | 10-15 min |
| 037 | Can't Pull Image — Registry Authentication Issues | Intermediate | 10-15 min |

### Kubernetes (12 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 025 | Pod CrashLoopBackOff | Intermediate | 10-15 min |
| 026 | Service Unreachable — Service Misconfigured | Intermediate | 10-15 min |
| 027 | External Traffic Blocked — Ingress Routing | Advanced | 15-20 min |
| 028 | PVC Stuck Pending | Advanced | 15-20 min |
| 029 | RBAC Permission Denied | Advanced | 15-20 min |
| 030 | Missing Config — ConfigMap and Secret Issues | Intermediate | 10-15 min |
| 031 | Can't Deploy — Resource Quota Exceeded | Intermediate | 10-15 min |
| 032 | HPA Not Scaling | Advanced | 15-20 min |
| 033 | Network Policy Too Restrictive | Advanced | 15-20 min |
| 034 | Pod Unschedulable — Node Affinity and Taints | Advanced | 15-20 min |
| 035 | Helm Chart Won't Install — Debug a Broken Chart | Advanced | 20-25 min |
| 036 | Wrong Config in Production — Helm Values and Overrides | Advanced | 20-25 min |

### Terraform / AWS (22 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 001 | VPC Networking — EC2 Can't Reach Internet | Intermediate-Advanced | 20-30 min |
| 002 | Terraform State Mismatch — Drift Detection | Advanced | 20-25 min |
| 003 | Module Won't Apply — Dependency Issues | Intermediate | 15-20 min |
| 004 | S3 Access Denied — Bucket Policy Debugging | Intermediate | 15-20 min |
| 005 | IAM Role Assumption Failed — Trust Policy | Advanced | 20-25 min |
| 006 | EC2 Can't Reach Internet — VPC Networking | Intermediate | 15-20 min |
| 007 | Database Unreachable — RDS Security Groups | Intermediate | 15-20 min |
| 008 | Lambda Can't Execute — Missing Permissions | Intermediate | 15-20 min |
| 009 | CloudFront Serving Stale Content — Caching | Advanced | 20-25 min |
| 010 | ASG Not Scaling — Auto Scaling Group Issues | Advanced | 20-25 min |
| 011 | Terraform Can't Authenticate — Provider Configuration | Intermediate | 10-15 min |
| 012 | Existing Resources — Terraform Import and Adoption | Advanced | 20-25 min |
| 013 | Wrong Environment — Terraform Workspace Confusion | Intermediate | 15-20 min |
| 014 | State File Lost — Remote Backend Configuration | Advanced | 20-25 min |
| 015 | Terraform Logic Errors — Conditionals and Loops | Intermediate | 15-20 min |
| 016 | Can't Reference Resources — Outputs and Data Sources | Intermediate | 15-20 min |
| 017 | DNS Failover Not Working — Route 53 Configuration | Advanced | 20-25 min |
| 018 | ECS Service Won't Start — Task Definition Errors | Advanced | 20-25 min |
| 019 | EKS Nodes Not Joining — Node Group Configuration | Advanced | 25-30 min |
| 020 | No Alerts Firing — CloudWatch Alarms Misconfigured | Intermediate | 15-20 min |
| 021 | Secrets Not Rotating — Secrets Manager Configuration | Advanced | 20-25 min |
| 022 | Cross-VPC Traffic Blocked — VPC Peering Issues | Advanced | 20-25 min |

### CI/CD Pipelines (5 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 040 | Pipeline Failing — GitHub Actions Debugging | Intermediate | 15-20 min |
| 041 | Secrets Not Available — Pipeline Credential Issues | Intermediate | 12-15 min |
| 042 | Bad Deploy — Rollback Strategy | Advanced | 20-25 min |
| 043 | Zero-Downtime Deploy — Blue/Green Switch | Advanced | 20-25 min |
| 044 | IaC Pipeline — Terraform in CI/CD | Advanced | 20-25 min |

### Monitoring & Incident Response (7 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 050 | Application Throwing 500s — Root Cause Analysis | Intermediate | 15-20 min |
| 051 | Memory Growing — Detect and Diagnose a Memory Leak | Advanced | 15-20 min |
| 052 | Logs Missing — Log Aggregation Pipeline Broken | Intermediate | 12-15 min |
| 053 | Too Many Alerts — Alert Fatigue Triage | Intermediate | 15-20 min |
| 054 | What Happened? — Post-Incident Timeline Reconstruction | Advanced | 20-25 min |
| 055 | No Metrics — Prometheus Scraping Broken | Intermediate | 15-20 min |
| 056 | Empty Dashboards — Grafana Data Source and Panel Debugging | Intermediate | 15-20 min |

### Capstone Projects (1 project)

| # | Project | Difficulty | Time |
|---|---------|-----------|------|
| 001 | Build From Scratch — Multi-Tier Application on Kubernetes | Expert | 60-90 min |

## How It Works

### Linux & Docker Labs (Docker-based)

Each lab is a Docker container with a deliberately introduced fault. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Start the lab with the runner tool or `docker compose up -d`
3. Exec into the container and diagnose the problem
4. Fix it
5. Run the validation to confirm your fix

**No internet required. No AWS costs. Fully local.**

### Kubernetes Labs

Each lab provides a set of broken Kubernetes manifests. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Apply the broken manifests: `kubectl apply -f manifests/broken/`
3. Use `kubectl` to diagnose the issues
4. Fix the resources (edit manifests or use `kubectl` directly)
5. Run `validate.sh` to confirm

**Requires a running Kubernetes cluster (kind, minikube, or cloud playground).**

### Cloud Infrastructure Labs (Terraform-based)

Each lab uses Terraform to provision a deliberately broken or incomplete AWS environment. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Run `terraform apply` to create the broken environment
3. Diagnose and fix the infrastructure (via console, CLI, or Terraform)
4. Run the validation script to confirm

**Requires an AWS account or KodeKloud Playground session.**

### CI/CD Pipeline Labs (File-based)

Each lab contains broken pipeline configs, deployment scripts, or workflow files. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Examine the pipeline configs and scripts in the lab directory
3. Identify and fix the issues
4. Run `validate.sh` to confirm

**No containers or cloud accounts needed — analyse and fix the files directly.**

### Monitoring & Incident Response Labs (Docker-based)

Each lab simulates a broken or misbehaving application in Docker. Your job is to:

1. Read the `CHALLENGE.md` for the scenario
2. Start the lab with the runner tool or `docker compose up -d`
3. Use logs, metrics, and debugging tools to diagnose the problem
4. Fix the root cause
5. Run the validation to confirm

**No internet required. No AWS costs. Fully local.**

### Capstone Projects

Projects are build-from-scratch exercises that combine skills across multiple categories. Unlike labs, there is no broken environment — you build the entire solution yourself.

1. Read the `CHALLENGE.md` for the full brief
2. Build the solution from scratch using the requirements provided
3. Run `validate.sh` to confirm your solution meets the acceptance criteria

**These are longer, open-ended exercises designed to test end-to-end skills.**

## Quick Start

```bash
# List all 74 labs + 1 project
./tools/labrunner.sh list

# Start a random lab
./tools/labrunner.sh random

# Filter by category
./tools/labrunner.sh random linux
./tools/labrunner.sh random k8s
./tools/labrunner.sh random cloud
./tools/labrunner.sh random cicd
./tools/labrunner.sh random monitoring
./tools/labrunner.sh random projects

# Start a specific lab
./tools/labrunner.sh start linux-labs/lab-001-nginx-down
./tools/labrunner.sh start k8s-labs/lab-025-pod-crash-loop
./tools/labrunner.sh start cicd-labs/lab-040-github-actions-broken
./tools/labrunner.sh start monitoring-labs/lab-050-app-500-errors
./tools/labrunner.sh start projects/project-001-build-multi-tier-app

# Validate your fix
./tools/labrunner.sh validate linux-labs/lab-001-nginx-down

# Track your progress
./tools/labrunner.sh progress
```

## Prerequisites

- Docker and Docker Compose (Linux, Docker & Monitoring labs)
- A Kubernetes cluster — kind, minikube, or remote (K8s labs)
- Helm 3 (Helm labs 035-036)
- Terraform + AWS CLI configured (Cloud labs)
- Bash 4+

## Building Your Own Labs

See [CREATING_LABS.md](CREATING_LABS.md) for the full guide on adding your own labs to this framework.
