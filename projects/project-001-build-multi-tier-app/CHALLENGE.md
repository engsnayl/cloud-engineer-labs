Title: Build and Deploy a Production-Ready Multi-Tier Application
Difficulty: ⭐⭐⭐⭐⭐ (Capstone)
Time: 3-4 hours
Category: End-to-End / Design, Build & Deploy
Skills: Terraform, Docker, Kubernetes, GitHub Actions, Prometheus, Grafana, AWS

## Scenario

You have been asked to build and deploy a production-ready three-tier web application from scratch. This is not a troubleshooting exercise -- there are no bugs to fix. You are given requirements and must design, containerise, provision infrastructure, deploy, and monitor the entire system end to end.

The application is a classic three-tier architecture: an nginx frontend serving static content and proxying API requests, a Python Flask backend providing REST endpoints, and a PostgreSQL database for persistent storage. You will containerise all three tiers, write Terraform to provision AWS infrastructure, create Kubernetes manifests for deployment, build a CI/CD pipeline with GitHub Actions, and add monitoring with Prometheus and Grafana.

This is the kind of project that belongs in a portfolio. Interviewers want to see that you can take requirements, make architectural decisions, and build a working system -- not just fix YAML indentation.

---

## Requirements

### Track 1: Terraform Infrastructure

Provision the AWS foundation for this application:

- **VPC** with public and private subnets across two availability zones
- **Security groups** for each tier (frontend, backend, database) with least-privilege rules
- **ECR repositories** for frontend and backend container images
- **Modular structure**: separate modules for networking, security, and ECR
- **Remote state**: S3 backend with DynamoDB locking
- **Outputs**: Export VPC ID, subnet IDs, ECR repository URLs, and security group IDs
- **Variables**: Region, project name, and environment should be configurable

### Track 2: Docker

Containerise all three tiers and enable local development:

- **Frontend Dockerfile**: nginx serving static HTML, custom nginx.conf for reverse proxying `/api/` to the backend
- **Backend Dockerfile**: Python Flask API with health, data, and metrics endpoints
- **docker-compose.yml**: Orchestrate all three tiers for local development with correct networking, environment variables, and volume mounts
- **.dockerignore files**: For both frontend and backend build contexts

### Track 3: Kubernetes

Deploy the full application to a Kubernetes cluster:

- **Namespace**: `multi-tier-app` to isolate all resources
- **Database layer**: Secret for credentials, ConfigMap for init SQL script, StatefulSet with PVC, headless Service
- **Backend layer**: Deployment (2 replicas), Service, ConfigMap for connection settings
- **Frontend layer**: Deployment (2 replicas), Service
- **Ingress**: Path-based routing -- `/` to frontend, `/api` to backend
- **NetworkPolicy**: Only backend pods can reach the database on port 5432
- **Health probes**: Readiness and liveness probes on frontend and backend
- **Resource limits**: CPU and memory requests/limits on all containers
- **Prometheus annotations**: Scrape annotations on the backend Deployment

### Track 4: CI/CD Pipeline

Build a GitHub Actions workflow that automates the full lifecycle:

- **Build stage**: Build frontend and backend Docker images
- **Test stage**: Run backend unit tests, lint Dockerfiles
- **Push stage**: Authenticate to ECR, tag images with git SHA, push to ECR
- **Deploy stage**: Update Kubernetes Deployments with new image tags
- **Secret management**: AWS credentials and kubeconfig stored as GitHub Secrets
- **Trigger**: On push to `main` branch, with path filters for relevant directories

### Track 5: Monitoring

Add observability to the deployed application:

- **Backend /metrics endpoint**: Expose Prometheus-format metrics (request counts, app info)
- **Prometheus scrape config**: ConfigMap with a scrape configuration targeting the backend pods
- **Grafana dashboard**: JSON dashboard definition showing request rates, health status, and pod metrics

### Track 6: Documentation

Produce documentation that an interviewer or teammate could follow:

- **README.md** with architecture diagram (ASCII), technology choices table, prerequisites, quick-start instructions for local and cluster deployment, CI/CD explanation, monitoring setup, project structure, and production considerations
- **Architecture decisions**: Why each technology was chosen, how services communicate, what would change for production

---

## Deliverables

Create these files in the `solution/` directory:

```
solution/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── backend.tf
│   └── modules/
│       ├── networking/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── security/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── ecr/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── docker/
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── .dockerignore
│   │   ├── nginx.conf
│   │   └── index.html
│   └── backend/
│       ├── Dockerfile
│       ├── .dockerignore
│       └── app.py
├── docker-compose.yml
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
│       └── deploy.yml
├── monitoring/
│   ├── prometheus-config.yaml
│   └── grafana-dashboard.json
└── README.md
```

---

## Acceptance Criteria

### Terraform
- [ ] `terraform fmt -check` passes with no formatting errors
- [ ] `terraform validate` passes
- [ ] VPC has public and private subnets in two AZs
- [ ] Security groups follow least-privilege (only required ports open)
- [ ] ECR repositories are created for frontend and backend images
- [ ] State is configured for S3 remote backend

### Docker
- [ ] `docker build` succeeds for both frontend and backend images
- [ ] `docker-compose up` starts all three tiers and the app is accessible at `http://localhost`
- [ ] Frontend proxies `/api/` requests to the backend
- [ ] Backend connects to the database and returns data from `/api/data`
- [ ] `.dockerignore` files exclude unnecessary build context

### Kubernetes
- [ ] All resources deploy without errors in the `multi-tier-app` namespace
- [ ] Database is a StatefulSet with persistent storage that survives pod restart
- [ ] Backend pods pass readiness probes and serve traffic
- [ ] Frontend serves HTML and proxies API requests through nginx
- [ ] Ingress routes `/` to frontend and `/api` to backend
- [ ] NetworkPolicy restricts database access to backend pods only
- [ ] All containers have resource requests and limits

### CI/CD
- [ ] GitHub Actions workflow has build, test, push, and deploy stages
- [ ] Images are tagged with git commit SHA (not `latest`)
- [ ] ECR push uses OIDC or access key authentication
- [ ] Deploy stage updates Kubernetes image references

### Monitoring
- [ ] Backend `/metrics` endpoint returns Prometheus-format text
- [ ] Prometheus scrape config targets the backend Service
- [ ] Grafana dashboard JSON is importable and shows relevant panels

### Documentation
- [ ] README includes architecture diagram, tech choices, and quick-start instructions
- [ ] Production considerations are documented

---

## Tips

- Build bottom-up: database first (no dependencies), then backend (depends on DB), then frontend (depends on backend), then networking.
- Test each tier with `kubectl port-forward` before adding Ingress.
- Use `echo -n "value" | base64` to generate Secret values.
- Start docker-compose locally to validate your app logic before deploying to Kubernetes.
- Run `terraform fmt` and `terraform validate` often as you write infrastructure code.

---

## Skills Checklist

When you complete this project, you should be able to tick every box:

- [ ] Terraform modules (networking, security, ECR)
- [ ] VPC design (public/private subnets, multi-AZ)
- [ ] Security Groups (least-privilege, tier-based)
- [ ] ECR (repository creation, lifecycle policies)
- [ ] Docker multi-tier builds (nginx, Python, PostgreSQL)
- [ ] docker-compose (multi-service local development)
- [ ] Kubernetes StatefulSets (database with persistent storage)
- [ ] Kubernetes Deployments (stateless frontend/backend)
- [ ] Kubernetes Services (ClusterIP, headless)
- [ ] Kubernetes Ingress (path-based routing)
- [ ] Kubernetes NetworkPolicy (pod-level firewall)
- [ ] Kubernetes ConfigMaps and Secrets
- [ ] Health probes (readiness and liveness)
- [ ] GitHub Actions (multi-stage CI/CD pipeline)
- [ ] ECR push (authenticate, tag, push from CI)
- [ ] Deployment gates (test before deploy)
- [ ] Prometheus metrics (exposition format, scrape config)
- [ ] Grafana dashboards (JSON model, panels, queries)
