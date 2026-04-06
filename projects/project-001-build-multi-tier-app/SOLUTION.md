# Solution Walkthrough -- Build and Deploy a Production-Ready Multi-Tier Application

## TLDR

This project builds a complete three-tier web application (nginx frontend, Flask backend, PostgreSQL database) and deploys it across three planes: local development with Docker Compose, Kubernetes on a Raspberry Pi running k3s, and AWS infrastructure provisioned with Terraform. It includes a GitHub Actions CI/CD pipeline and Prometheus/Grafana monitoring. By the end, you will have demonstrated Terraform module design, Docker containerisation, Kubernetes orchestration, CI/CD automation, and observability -- the core skills expected of a mid-level cloud/DevOps engineer.

---

## Thought Process

When building a multi-tier system, experienced engineers work bottom-up and inside-out:

1. **Infrastructure first** -- provision the network and registries that everything else depends on.
2. **Database layer** -- no dependencies on other application components; get data persistence working.
3. **Backend layer** -- depends only on the database; verify connectivity before moving on.
4. **Frontend layer** -- depends on the backend; validates the full request chain.
5. **Networking** -- Ingress and NetworkPolicy tie everything together and add security.
6. **Local dev environment** -- Docker Compose lets you iterate without a cluster.
7. **CI/CD** -- automate what you have been doing manually.
8. **Monitoring** -- observe the running system.
9. **Documentation** -- explain what you built and why.

This order means each layer can be tested independently. If the backend cannot connect to the database, you know the problem is in the backend configuration, not the database -- because you already verified the database works.

---

## Step 1: Terraform Infrastructure (VPC, ECR, Security Groups)

### What we are building

AWS networking and container registry infrastructure using a modular Terraform layout:

```
solution/terraform/
├── main.tf           # Root module, composes child modules
├── variables.tf      # Input variables (region, project name, environment)
├── outputs.tf        # Exported values (VPC ID, ECR URLs, etc.)
├── providers.tf      # AWS provider configuration
├── backend.tf        # S3 remote state configuration
└── modules/
    ├── networking/   # VPC, subnets, internet gateway, route tables
    ├── security/     # Security groups per tier
    └── ecr/          # ECR repositories for frontend and backend
```

### Why this structure

Terraform modules are reusable, testable units. Separating networking from security from ECR means you can modify security group rules without risking your VPC configuration. The root module composes the child modules and passes outputs between them.

### Key decisions

- **Two AZs** for high availability. Subnets in `eu-west-2a` and `eu-west-2b`.
- **Public subnets** for load balancers, **private subnets** for application workloads. The database never sits in a public subnet.
- **S3 backend with DynamoDB locking** prevents two engineers from running `terraform apply` simultaneously and corrupting state.
- **ECR lifecycle policies** keep only the last 30 images to control storage costs.
- Security groups follow least-privilege: frontend allows 80/443 inbound, backend allows 8080 only from frontend SG, database allows 5432 only from backend SG.

### How to verify

```bash
cd solution/terraform
terraform fmt -check        # Should exit 0 (no formatting issues)
terraform init              # Initialise providers and modules
terraform validate          # Check syntax and references
terraform plan              # Review what will be created (do NOT apply unless you want AWS costs)
```

| Flag | Purpose |
|------|---------|
| `fmt -check` | Validates formatting without modifying files; exits non-zero if changes needed |
| `init` | Downloads provider plugins and initialises module references |
| `validate` | Checks HCL syntax, variable references, and resource dependencies |
| `plan` | Generates an execution plan showing what would be created, changed, or destroyed |

---

## Step 2: Database Layer (Secret, ConfigMap, StatefulSet, Service)

### What we are building

PostgreSQL running as a Kubernetes StatefulSet with persistent storage, credentials in a Secret, and an init script in a ConfigMap.

### Files

- `k8s/namespace.yaml` -- creates the `multi-tier-app` namespace
- `k8s/database-secret.yaml` -- base64-encoded `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`
- `k8s/database-init-configmap.yaml` -- SQL script that creates the `items` table and inserts seed data
- `k8s/database-pvc.yaml` -- 1Gi PersistentVolumeClaim with ReadWriteOnce access
- `k8s/database-statefulset.yaml` -- single-replica StatefulSet mounting the PVC and init script
- `k8s/database-service.yaml` -- headless Service (`clusterIP: None`) for stable DNS

### Why StatefulSet instead of Deployment

Deployments are designed for stateless workloads. StatefulSets provide: stable pod names (`postgres-0`), ordered startup/shutdown, and persistent volume association that survives rescheduling. All three properties are essential for databases.

### Key decisions

- `subPath: pgdata` on the volume mount. PostgreSQL refuses to start if the data directory is not empty. Without the subPath, the PVC root may contain `lost+found`, which causes a boot failure.
- `envFrom: secretRef` injects all Secret keys as environment variables. The official postgres image reads `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` automatically.
- The init ConfigMap mounts at `/docker-entrypoint-initdb.d/`. The official image executes `.sql` files in that directory on first boot only.
- `ON CONFLICT DO NOTHING` in the init SQL makes inserts idempotent.

### How to verify

```bash
kubectl apply -f solution/k8s/namespace.yaml
kubectl apply -f solution/k8s/database-secret.yaml
kubectl apply -f solution/k8s/database-init-configmap.yaml
kubectl apply -f solution/k8s/database-pvc.yaml
kubectl apply -f solution/k8s/database-statefulset.yaml
kubectl apply -f solution/k8s/database-service.yaml

kubectl wait --for=condition=ready pod/postgres-0 -n multi-tier-app --timeout=60s
kubectl exec -n multi-tier-app postgres-0 -- psql -U appuser -d appdb -c "SELECT * FROM items;"
```

You should see three rows of seed data. If you delete the pod and wait for it to restart, the data should still be there -- that confirms the PVC is working.

---

## Step 3: Backend Layer (app.py, Dockerfile, Deployment, Service, ConfigMap)

### What we are building

A Python Flask REST API with three endpoints:

- `/api/health` -- returns database connectivity status (used by K8s probes)
- `/api/data` -- queries the `items` table and returns JSON
- `/metrics` -- exposes Prometheus-format metrics

### Files

- `docker/backend/app.py` -- Flask application
- `docker/backend/Dockerfile` -- based on `python:3.11-slim`, installs flask and psycopg2-binary
- `docker/backend/.dockerignore` -- excludes `__pycache__`, `.git`, `*.pyc`
- `k8s/backend-configmap.yaml` -- non-sensitive config: `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`
- `k8s/backend-deployment.yaml` -- 2 replicas with health probes, resource limits, Prometheus annotations
- `k8s/backend-service.yaml` -- ClusterIP Service on port 8080

### Key decisions

- The password comes from `secretKeyRef` referencing the database Secret, not from the ConfigMap. Never put credentials in ConfigMaps.
- `readinessProbe` hits `/api/health` so Kubernetes only routes traffic to pods that have a working database connection.
- `livenessProbe` hits the same endpoint with a longer interval. If the database connection is persistently broken, the pod restarts.
- Prometheus annotations (`prometheus.io/scrape: "true"`, `prometheus.io/port: "8080"`, `prometheus.io/path: "/metrics"`) enable auto-discovery scraping.
- Resource limits prevent a runaway process from consuming all node resources. Requests guarantee a baseline allocation.

### How to verify

```bash
docker build -t backend:latest solution/docker/backend/

kubectl apply -f solution/k8s/backend-configmap.yaml
kubectl apply -f solution/k8s/backend-deployment.yaml
kubectl apply -f solution/k8s/backend-service.yaml

kubectl rollout status deployment/backend -n multi-tier-app --timeout=60s
kubectl port-forward -n multi-tier-app svc/backend-service 8080:8080 &
curl http://localhost:8080/api/health
curl http://localhost:8080/api/data
curl http://localhost:8080/metrics
kill %1
```

The health endpoint should return `{"status": "healthy", "database": "connected"}`. The data endpoint should return the three seed items. The metrics endpoint should return plain text in Prometheus exposition format.

---

## Step 4: Frontend Layer (nginx, HTML, Dockerfile, Deployment, Service)

### What we are building

An nginx web server that serves a static HTML page and reverse proxies `/api/` requests to the backend.

### Files

- `docker/frontend/index.html` -- single-page app that fetches `/api/health` and `/api/data` via JavaScript
- `docker/frontend/nginx.conf` -- serves static files at `/`, proxies `/api/` to `backend-service:8080`
- `docker/frontend/Dockerfile` -- based on `nginx:alpine`, copies config and HTML
- `docker/frontend/.dockerignore` -- excludes `.git`, `*.md`
- `k8s/frontend-deployment.yaml` -- 2 replicas with readiness probe on port 80
- `k8s/frontend-service.yaml` -- ClusterIP Service on port 80

### Key decisions

- `nginx:alpine` keeps the image under 50MB. There is no application runtime -- just a web server.
- The `proxy_pass` directive uses the Kubernetes Service name `backend-service:8080`. DNS resolution within the cluster handles the rest.
- `proxy_set_header` lines forward client IP and protocol information to the backend for logging and security.
- `try_files $uri $uri/ /index.html` supports single-page app routing.

### How to verify

```bash
docker build -t frontend:latest solution/docker/frontend/

kubectl apply -f solution/k8s/frontend-deployment.yaml
kubectl apply -f solution/k8s/frontend-service.yaml

kubectl rollout status deployment/frontend -n multi-tier-app --timeout=60s
kubectl port-forward -n multi-tier-app svc/frontend-service 8081:80 &
curl http://localhost:8081/
kill %1
```

You should see the HTML page content. Opening it in a browser should show health status and database items.

---

## Step 5: Networking (Ingress, NetworkPolicy)

### What we are building

External access via Ingress path-based routing and internal security via NetworkPolicy.

### Files

- `k8s/ingress.yaml` -- routes `/api` to backend-service:8080, `/` to frontend-service:80
- `k8s/network-policy.yaml` -- restricts database ingress to backend pods on port 5432

### Key decisions

- The `/api` path is listed before `/` in the Ingress because rules match most-specific-first.
- The NetworkPolicy uses `podSelector` on both the target (postgres) and the allowed source (backend). Only pods labelled `app: backend` can reach port 5432 on pods labelled `app: postgres`.
- On k3s, Traefik is the default Ingress Controller. If using k3s, you may need to adjust the `ingressClassName` or annotations. The solution includes comments noting this.
- k3s uses Flannel by default, which does not enforce NetworkPolicies. The manifest is still correct and would work on clusters running Calico or Cilium.

### How to verify

```bash
kubectl apply -f solution/k8s/ingress.yaml
kubectl apply -f solution/k8s/network-policy.yaml

kubectl get ingress -n multi-tier-app
curl http://localhost/api/health
curl http://localhost/
```

| Command | What it checks |
|---------|---------------|
| `kubectl get ingress` | Confirms the Ingress resource was created and has an address |
| `curl /api/health` | Validates end-to-end routing through Ingress to backend to database |
| `curl /` | Validates frontend is served through Ingress |

---

## Step 6: Docker Compose for Local Development

### What we are building

A `docker-compose.yml` that runs all three tiers locally so you can develop and test without a Kubernetes cluster.

### File

- `docker-compose.yml` at the solution root

### Key decisions

- The database uses `postgres:15` directly (no custom Dockerfile needed).
- The backend `depends_on` the database with a health check condition, so it waits for PostgreSQL to accept connections before starting.
- The frontend maps port 80 on localhost so you access the app at `http://localhost`.
- Environment variables mirror what the Kubernetes ConfigMap and Secret provide.
- A named volume `postgres-data` persists database files across `docker-compose down` / `docker-compose up` cycles.
- The init SQL script is bind-mounted into `/docker-entrypoint-initdb.d/`.

### How to verify

```bash
cd solution
docker-compose up --build -d
curl http://localhost/api/health
curl http://localhost/api/data
docker-compose down
```

The health check should return `healthy` and the data endpoint should return the seed items.

---

## Step 7: CI/CD Pipeline Setup

### What we are building

A GitHub Actions workflow at `solution/.github/workflows/deploy.yml` with four stages: build, test, push to ECR, and deploy to Kubernetes.

### Key decisions

- **Trigger**: `on: push` to `main` with path filters so the pipeline only runs when application or infrastructure code changes.
- **Build stage**: Uses `docker/build-push-action` to build both images. Tagged with `${{ github.sha }}` for traceability -- never `latest` in CI.
- **Test stage**: Runs backend tests and Dockerfile linting with hadolint.
- **Push stage**: Authenticates to ECR using `aws-actions/amazon-ecr-login`. Pushes both images tagged with the git commit SHA.
- **Deploy stage**: Uses `kubectl set image` to update the Deployment image references. This triggers a rolling update.
- **Secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, and `KUBE_CONFIG` are stored as GitHub repository secrets.

### How to verify

The workflow file should be valid YAML. You can lint it locally:

```bash
# If you have actionlint installed:
actionlint solution/.github/workflows/deploy.yml
```

To test the full pipeline, push to a GitHub repository with the required secrets configured. The Actions tab will show each stage's status.

---

## Step 8: Monitoring (Prometheus Config, Grafana Dashboard)

### What we are building

- A Prometheus scrape configuration that targets the backend pods
- A Grafana dashboard definition that visualises application metrics

### Files

- `monitoring/prometheus-config.yaml` -- Kubernetes ConfigMap containing `prometheus.yml` with scrape targets
- `monitoring/grafana-dashboard.json` -- importable dashboard with panels for request rates, health status, and pod info

### Key decisions

- The Prometheus config uses `kubernetes_sd_configs` with pod role and annotation-based filtering. Pods with `prometheus.io/scrape: "true"` are discovered automatically.
- The Grafana dashboard uses Prometheus as its datasource and includes panels for `http_requests_total` rate, `app_info` gauge, and up/down status.
- For a learning environment, install the kube-prometheus-stack via Helm:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

- Access Grafana with port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# Default credentials: admin / prom-operator
```

- Import the dashboard via Grafana UI: Dashboards > Import > Upload JSON file.

### How to verify

```bash
# Check the metrics endpoint is working
kubectl port-forward -n multi-tier-app svc/backend-service 8080:8080 &
curl http://localhost:8080/metrics
kill %1

# Check Prometheus is scraping (after Helm install)
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090/targets -- backend should appear as a target
```

---

## Step 9: Documentation and Final Validation

### What we are building

The `solution/README.md` that an interviewer or teammate would read to understand the project.

### What to include

- ASCII architecture diagram showing all components and their connections
- Technology choices table with rationale for each decision
- Prerequisites (tools, accounts, secrets)
- Quick-start instructions for Docker Compose, Kubernetes, and Terraform
- CI/CD pipeline explanation
- Monitoring setup guide
- Project directory tree
- Production considerations table (learning version vs production)

### How to verify

Run the validation script:

```bash
bash validate.sh
```

All checks should pass. Then do a manual end-to-end walkthrough:

1. `docker-compose up` -- app works locally
2. Deploy to k3s -- all pods running, Ingress accessible
3. `terraform validate` -- infrastructure code is valid
4. Metrics endpoint returns Prometheus format data
5. README is clear enough that someone unfamiliar with the project could follow it

---

## Project vs Real Life

| Aspect | This Project | Production |
|--------|-------------|------------|
| **Database** | PostgreSQL in a StatefulSet | Managed service (RDS, Aurora, Cloud SQL) with automated backups and failover |
| **TLS/HTTPS** | No encryption | cert-manager with Let's Encrypt or ACM certificates on ALB |
| **Scaling** | Fixed 2 replicas | Horizontal Pod Autoscaler based on CPU, memory, or custom metrics |
| **Secrets** | Kubernetes Secrets (base64) | External Secrets Operator pulling from AWS Secrets Manager or HashiCorp Vault |
| **CI/CD runners** | GitHub-hosted runners | Self-hosted runners in a private subnet for security and speed |
| **Image tags** | `latest` locally, SHA in CI | Semantic versioning with signed images (cosign/Notary) |
| **Terraform state** | Local or S3 | S3 with DynamoDB locking, state file encryption, and access controls |
| **Monitoring** | Basic metrics endpoint | Full Prometheus stack with alerting rules, PagerDuty integration, SLO dashboards |
| **Logging** | Container stdout | Fluent Bit DaemonSet forwarding to CloudWatch, Elasticsearch, or Loki |
| **Environments** | Single namespace | Separate namespaces or clusters for dev, staging, production with promotion gates |
| **Network** | NetworkPolicy | Service mesh (Istio/Linkerd) with mTLS, traffic policies, and circuit breakers |
| **DNS** | localhost / Pi IP | Route 53 with custom domain, health checks, and failover routing |
| **Backup** | None | Automated pg_dump to S3 with retention policies, or RDS automated snapshots |

---

## Key Concepts Learned

- **Terraform module composition** -- breaking infrastructure into reusable, independently testable modules
- **VPC design** -- public vs private subnets, multi-AZ for high availability, Internet Gateway routing
- **Security groups** -- stateful firewalls with least-privilege rules referencing other security groups
- **ECR** -- private container registry with lifecycle policies for cost control
- **Docker multi-stage awareness** -- slim/alpine base images, .dockerignore to reduce build context
- **docker-compose** -- multi-service local development with dependency ordering and health checks
- **Kubernetes StatefulSets** -- stable identity, ordered operations, and persistent storage for databases
- **Kubernetes Deployments** -- declarative replica management with rolling updates for stateless services
- **Services and DNS** -- ClusterIP for internal routing, headless for StatefulSets, Kubernetes DNS resolution
- **Ingress** -- layer 7 path-based routing for external access through a single entry point
- **NetworkPolicy** -- pod-level firewall rules enforcing least-privilege communication
- **ConfigMaps vs Secrets** -- separating non-sensitive configuration from credentials
- **Health probes** -- readiness (traffic routing) vs liveness (pod restart) for self-healing
- **Resource requests and limits** -- guaranteeing baseline resources and preventing noisy-neighbour issues
- **GitHub Actions** -- multi-stage CI/CD with secret management and conditional deployment
- **ECR authentication** -- aws-actions for registry login, SHA-based image tagging for traceability
- **Prometheus metrics** -- exposition format, scrape configuration, annotation-based auto-discovery
- **Grafana dashboards** -- JSON dashboard models, PromQL queries, panel configuration
- **Bottom-up deployment** -- building and testing each dependency layer before adding the next

---

## Cleanup

> **WARNING: Do not skip this section. AWS resources cost money. Terraform resources will continue to incur charges until destroyed.**

### 1. Terraform -- Destroy AWS Infrastructure

```bash
cd solution/terraform
terraform destroy
```

Type `yes` when prompted. Verify in the AWS Console that the VPC, subnets, security groups, and ECR repositories have been removed. Check the S3 bucket for the state file if you want to clean that up separately.

### 2. Kubernetes -- Delete the Namespace

```bash
kubectl delete namespace multi-tier-app
```

This removes every resource in the namespace: pods, services, deployments, statefulsets, PVCs, secrets, configmaps, ingress, and network policies. One command.

### 3. Docker -- Clean Up Local Resources

```bash
docker-compose down -v          # Stop containers and remove volumes
docker rmi frontend:latest backend:latest   # Remove built images
docker system prune -f          # Remove dangling images and build cache
```

### 4. Monitoring Stack (if installed)

```bash
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

Verify nothing is left running:

```bash
kubectl get namespaces          # multi-tier-app and monitoring should be gone
docker ps -a                    # No project containers running
```
