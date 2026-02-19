# Cloud Engineer Labs

A self-directed lab framework for practising real-world cloud engineering and Linux troubleshooting skills. Each lab simulates a realistic broken or incomplete environment that you must diagnose and fix — just like you would on the job.

**41 labs** across four categories: Linux, Docker, Kubernetes, and Terraform/AWS.

## Structure

```
cloud-engineer-labs/
├── linux-labs/          # Linux + Docker troubleshooting labs (21 labs)
│   ├── lab-001 … lab-015   (Linux)
│   └── lab-019 … lab-024   (Docker)
├── k8s-labs/            # Kubernetes troubleshooting labs (10 labs)
│   └── lab-025 … lab-034
├── cloud-labs/          # Terraform / AWS infrastructure labs (10 labs)
│   └── lab-001 … lab-010
├── tools/
│   └── labrunner.sh     # CLI runner
├── CREATING_LABS.md
└── README.md
```

## Lab Catalogue

### Linux Troubleshooting (15 labs)

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

### Docker Troubleshooting (6 labs)

| # | Lab | Difficulty | Time |
|---|-----|-----------|------|
| 019 | Container Won't Start | Intermediate | 10-15 min |
| 020 | Containers Can't Talk — Network Issues | Intermediate | 12-15 min |
| 021 | Data Missing — Volume Mount Problems | Intermediate | 10-15 min |
| 022 | Build Broken — Dockerfile Debugging | Intermediate | 10-15 min |
| 023 | Compose Chaos — Multi-Container App Broken | Advanced | 15-20 min |
| 024 | Container Keeps Dying — OOM Kills | Advanced | 12-15 min |

### Kubernetes (10 labs)

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

### Terraform / AWS (10 labs)

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

## Quick Start

```bash
# List all 41 labs
./tools/labrunner.sh list

# Start a random lab
./tools/labrunner.sh random

# Filter by category
./tools/labrunner.sh random linux
./tools/labrunner.sh random k8s
./tools/labrunner.sh random cloud

# Start a specific lab
./tools/labrunner.sh start linux-labs/lab-001-nginx-down
./tools/labrunner.sh start k8s-labs/lab-025-pod-crash-loop

# Validate your fix
./tools/labrunner.sh validate linux-labs/lab-001-nginx-down

# Track your progress
./tools/labrunner.sh progress
```

## Prerequisites

- Docker and Docker Compose (Linux & Docker labs)
- A Kubernetes cluster — kind, minikube, or remote (K8s labs)
- Terraform + AWS CLI configured (cloud labs)
- Bash 4+

## Building Your Own Labs

See [CREATING_LABS.md](CREATING_LABS.md) for the full guide on adding your own labs to this framework.
