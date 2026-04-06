# Project 001 — Video Series Plan

## Series Title: "Building a Production-Ready Multi-Tier App from Scratch"

A step-by-step video series covering the full capstone project — from empty directory to running application with infrastructure, containers, Kubernetes, CI/CD, and monitoring.

**Total episodes:** 11
**Target runtime:** ~30 minutes each (~5.5 hours total)
**Format:** Screen recording with narration, building everything live

---

## Episode 0: Project Overview & Environment Setup

**Title:** "What We're Building and Why It Matters"
**Runtime target:** 25-30 min

### What to cover:
- **Opening** — Introduce the series: "Over the next 10 episodes, we're going to build a complete three-tier application from scratch — and by the end, you'll have touched every major skill a cloud engineer uses day to day."
- **The interview narrative** — Explain why this project exists: what you'll be able to say in interviews once it's complete, and how each track maps to real job requirements
- **Architecture walkthrough** — Draw or show the full architecture diagram: AWS infrastructure, Docker containers, Kubernetes cluster, CI/CD pipeline, monitoring stack. Explain how data flows from browser to database and back.
- **Tour of the tech stack** — Brief intro to each tool (Terraform, Docker, Flask, nginx, PostgreSQL, Kubernetes, GitHub Actions, Prometheus, Grafana) and what role it plays
- **Environment check** — Show the Pi setup: verify Docker, k3s, kubectl, Terraform, AWS CLI are installed and working. Show the AWS console briefly (VPC section, ECR section — both empty, about to be built).
- **Clone the repo** — Pull down the project skeleton, walk through the directory structure, show what we're about to build

### Key talking points:
- Why three tiers? (separation of concerns, independent scaling, security boundaries)
- Why bottom-up build order? (each layer depends on the one below)
- What "production-ready" means vs what we're building (set expectations)

### Deliverable by end of episode:
Working development environment with all tools installed and verified

---

## Episode 1: AWS Infrastructure with Terraform

**Title:** "Provisioning Cloud Infrastructure with Terraform"
**Runtime target:** 30-35 min

### What to cover:
- **What is Terraform?** — Infrastructure as code concept. "Instead of clicking around the AWS console, we write code that describes what we want, and Terraform builds it."
- **Module structure** — Walk through the terraform/ directory. Explain why we split into modules (vpc/, ecr/) instead of one giant file.
- **VPC module** — Build it live or walk through each resource:
  - VPC + CIDR block (what is a CIDR, what is a VPC)
  - Public vs private subnets (why two of each, what AZs are)
  - Internet Gateway (how public subnets reach the internet)
  - NAT Gateway (how private subnets reach the internet without being exposed)
  - Route tables and associations (how traffic knows where to go)
- **ECR module** — Explain what a container registry is, create the two repos, show the lifecycle policy (cost control)
- **Security Groups** — Walk through the least-privilege chain: frontend SG → backend SG → database SG. Show how each SG only allows traffic from the one above it.
- **Root module** — Show how main.tf ties the modules together, variables, outputs
- **Live demo** — Run `terraform init`, `terraform plan` (walk through the plan output), `terraform apply`. Show the created resources in the AWS console.
- **Remote state** — Explain why it matters (team collaboration, state locking), show the commented-out backend.tf config
- **Cost warning** — Emphasise the NAT Gateway costs ~$0.045/hr. Always `terraform destroy` when done.

### Key talking points:
- Modules = reusability and organisation
- Plan before apply = safety net
- State file = Terraform's memory of what it built
- Always destroy when learning to avoid surprise bills

### Deliverable by end of episode:
VPC, subnets, IGW, NAT GW, security groups, and ECR repos all live in AWS

---

## Episode 2: Building the Backend — Flask API & Docker

**Title:** "Containerising a Python API with Docker"
**Runtime target:** 30 min

### What to cover:
- **What is Flask?** — Lightweight Python web framework. Show app.py and walk through each section:
  - Imports and what each library does
  - Database connection helper (why environment variables, why not hardcode)
  - `/api/health` — What health checks are and why Kubernetes needs them
  - `/api/data` GET — Reading from the database, parameterized queries (SQL injection prevention)
  - `/api/data` POST — Writing to the database, input validation
  - `/metrics` — Prometheus metrics with Counter and Histogram (what each measures)
- **requirements.txt** — What each package does and why we pin versions
- **The Dockerfile** — Build it line by line:
  - Base image choice (python:3.11-slim — why slim, why not alpine for Python)
  - Layer caching trick (copy requirements first, then code)
  - Why gunicorn instead of Flask's dev server
  - EXPOSE as documentation vs actual port opening
- **.dockerignore** — What it does and why it matters (smaller images, no secrets leaked)
- **Build and test** — `docker build`, then run the container with a postgres container alongside it to prove the API works. Hit the endpoints with curl.
- **Multi-stage build discussion** — Explain what it is and why we don't need one here (small app, no compile step)

### Key talking points:
- Containers = consistent environment everywhere ("works on my machine" solved)
- Layer caching = fast rebuilds during development
- Gunicorn = production server, Flask dev server = development only
- Never hardcode credentials — always use environment variables

### Deliverable by end of episode:
Working backend Docker image that serves all API endpoints

---

## Episode 3: Building the Frontend — nginx & Docker

**Title:** "Static Hosting and Reverse Proxying with nginx"
**Runtime target:** 25-30 min

### What to cover:
- **What is nginx?** — Web server and reverse proxy. Two jobs in our architecture: serve HTML files and forward API requests.
- **nginx.conf walkthrough** — Line by line:
  - events block (worker connections)
  - http block (mime types — what happens without them)
  - server block (listen 80, server_name)
  - location /api/ (proxy_pass, what a reverse proxy does, proxy headers and why they matter)
  - location / (static file serving, try_files for SPA routing)
- **index.html walkthrough** — Walk through the key sections:
  - HTML structure and CSS (brief — not a frontend course)
  - JavaScript: fetch() calls to /api/health and /api/data
  - Why relative URLs (/api/data not http://backend:5000/api/data) — same-origin, the proxy handles routing
  - The add-item form and POST request
- **The Dockerfile** — Much simpler than the backend:
  - nginx:1.25-alpine (why Alpine works great for nginx)
  - Remove default config, copy ours
  - daemon off (why containers need foreground processes)
- **Build and test** — Build the image, run it alongside the backend + postgres, open in browser

### Key talking points:
- Reverse proxy pattern = single entry point, backend is hidden
- CORS is avoided because the browser sees everything as one origin
- Alpine + nginx = tiny image (~40MB)
- Static files are served directly, API calls are forwarded — nginx decides based on the URL path

### Deliverable by end of episode:
Working frontend Docker image that serves the page and proxies API calls

---

## Episode 4: Local Development with Docker Compose

**Title:** "Running the Full Stack Locally with Docker Compose"
**Runtime target:** 25-30 min

### What to cover:
- **What is Docker Compose?** — A tool for defining multi-container applications. "One command to start everything."
- **Why Compose?** — Compare the alternative: manually running 3 `docker run` commands with networks, volumes, and environment variables vs one `docker-compose up`
- **docker-compose.yml walkthrough** — Service by service:
  - **postgres** — Image, environment variables from the service definition, volume for persistence, healthcheck (what it does, why the backend needs to wait for it)
  - **backend** — build context, depends_on with condition: service_healthy (why this matters — race conditions), environment variables, port mapping
  - **frontend** — build context, depends_on, port 8080:80 (why 8080 — Traefik on the Pi uses 80)
  - **volumes** — Named volume for postgres data (survives `docker-compose down`)
- **Live demo** — Run `docker-compose up --build`, watch all three services start, show the dependency ordering in the logs
- **Test it** — Open browser to localhost:8080, show the app working, add an item, show it persists
- **Compare to Kubernetes** — "Compose is great for local dev, but it runs on ONE machine. Kubernetes spreads your app across a cluster with self-healing, scaling, and rolling updates."
- **Cleanup** — `docker-compose down -v` (explain the -v flag — removes volumes too)

### Key talking points:
- Compose = local development, Kubernetes = production deployment
- depends_on with healthchecks = proper startup ordering
- Named volumes = data survives restarts, -v flag = clean slate
- This is a common interview question: "How do developers run this locally?"

### Deliverable by end of episode:
Full three-tier app running locally via Compose, accessible in browser

---

## Episode 5: Kubernetes — Database Layer

**Title:** "Deploying PostgreSQL on Kubernetes with Persistent Storage"
**Runtime target:** 30-35 min

### What to cover:
- **Brief K8s refresher** — Pods, Deployments, Services, Namespaces (30-second version — link to earlier labs for deep dives)
- **Namespace** — Create multi-tier-app namespace. Why namespaces matter (isolation, organisation, RBAC).
- **Secret** — Walk through database-secret.yaml:
  - What Secrets are and how they differ from ConfigMaps
  - base64 encoding (demo encoding/decoding on command line)
  - Why base64 is NOT encryption — what you'd use in production (Vault, External Secrets)
- **Init ConfigMap** — Walk through the SQL init script:
  - How PostgreSQL's docker-entrypoint-initdb.d mechanism works
  - The CREATE TABLE statement (what SERIAL, VARCHAR, TIMESTAMP mean)
  - Seed data (why pre-populate — so the API has something to show)
- **StatefulSet** — The main event. Walk through database-statefulset.yaml:
  - Why StatefulSet not Deployment (stable identity, stable storage, ordered ops)
  - Container spec (image, ports, env from Secret)
  - The PGDATA subpath trick (why, what happens without it — lost+found gotcha)
  - Volume mounts (data + init script)
  - volumeClaimTemplates (what PVCs are, ReadWriteOnce, how storage provisioning works)
  - Resource requests and limits
- **Headless Service** — Why clusterIP: None for a StatefulSet (direct pod DNS)
- **Deploy and verify** — Apply in order, wait for ready, check logs, exec into psql, query the seed data
- **Kill the pod** — Delete postgres-0, watch it come back with the same data (prove persistence works)

### Key talking points:
- StatefulSet = databases, Deployment = everything else
- PVCs = data survives pod restarts (the whole point of persistent storage)
- The PGDATA subpath is a real-world gotcha that catches many people
- Always verify each layer works before building the next one on top

### Deliverable by end of episode:
PostgreSQL running in Kubernetes with persistent storage, verified with psql

---

## Episode 6: Kubernetes — Application Layer

**Title:** "Deploying the Backend and Frontend to Kubernetes"
**Runtime target:** 30 min

### What to cover:
- **Build and import images** — docker build both images, docker save | k3s ctr images import (explain why this step is needed — k3s uses containerd, not Docker)
- **Backend ConfigMap** — Walk through backend-configmap.yaml:
  - Why separate config from code (12-factor app principle)
  - How Kubernetes DNS works (Service name = hostname within the namespace)
- **Backend Deployment** — Walk through backend-deployment.yaml:
  - Replicas (2 — why redundancy matters)
  - envFrom (bulk import from ConfigMap) vs env with valueFrom (selective import from Secret)
  - Readiness probe vs liveness probe (what each does, what happens when they fail)
  - Why different initialDelaySeconds for each (give app time to start)
  - Rolling update strategy (maxSurge, maxUnavailable — zero-downtime deploys)
  - Resource requests vs limits (scheduling vs enforcement)
  - Prometheus annotations (what they do — tell Prometheus where to scrape)
- **Backend Service** — ClusterIP, port mapping, selector matching
- **Test backend** — port-forward, curl health and data endpoints, verify database connection
- **Frontend Deployment** — Walk through (similar to backend but simpler — no env vars, lighter resources, different probes)
- **Frontend Service** — ClusterIP on port 80
- **Test frontend** — port-forward to 8080:80, open in browser (API calls will fail — expected, because port-forward bypasses the proxy)

### Key talking points:
- envFrom vs env — when to use each
- Readiness = "don't send traffic yet", Liveness = "restart me, I'm broken"
- Prometheus annotations = opt-in monitoring without changing the app
- Port-forward = temporary debugging tunnel, not how real traffic flows

### Deliverable by end of episode:
Backend and frontend pods running with health checks passing

---

## Episode 7: Kubernetes — Networking & Going Live

**Title:** "Ingress Routing, Network Security, and Going Live"
**Runtime target:** 30 min

### What to cover:
- **What is Ingress?** — The front door. One entry point, path-based routing to different services.
- **Ingress Controller** — Explain that an Ingress resource alone does nothing — you need a controller. k3s comes with Traefik built in (vs nginx Ingress Controller on other clusters).
- **Ingress manifest** — Walk through ingress.yaml:
  - Path-based routing (/api → backend, / → frontend)
  - Why most-specific-match-wins matters
  - Annotations for nginx vs Traefik (show both, explain we use Traefik on k3s)
- **NetworkPolicy** — Walk through network-policy.yaml:
  - Default K8s networking = everything talks to everything (why that's bad)
  - Our policy: only backend pods can reach the database on port 5432
  - podSelector (who is protected), from (who is allowed), ports (what's allowed)
  - **Flannel caveat** — k3s default CNI doesn't enforce it. Manifest is correct but unenforced. Mention Calico/Cilium for enforcement.
- **The deploy script** — Walk through deploy.sh. Explain why ordering matters (namespace first, then configs, then workloads).
- **Go live** — Apply ingress + network policy, find Pi's IP, open in browser on another device
- **Full demo** — Show the app working end-to-end: health badge, items list, add a new item, refresh, see it persist
- **Test from another device** — Phone or laptop on the same network, open http://<pi-ip>

### Key talking points:
- Ingress = the public face of your cluster
- NetworkPolicy = internal firewall (defence in depth)
- deploy.sh = reproducible, ordered deployments (not just "apply everything and hope")
- The app is now live and accessible on the network

### Deliverable by end of episode:
Fully working application accessible via browser from any device on the network

---

## Episode 8: CI/CD Pipeline with GitHub Actions

**Title:** "Automating Build, Test, and Deploy with GitHub Actions"
**Runtime target:** 30 min

### What to cover:
- **What is CI/CD?** — Continuous Integration (build + test on every push) and Continuous Deployment (automatically deploy). "You push code, the pipeline does the rest."
- **GitHub Actions basics** — Workflows, jobs, steps, triggers. How .github/workflows/ works.
- **Workflow walkthrough** — Walk through deploy.yml stage by stage:
  - **Trigger** — on push to main, with path filter (only runs when project files change)
  - **Build stage** — Checkout, set up Docker Buildx (what it is), build both images
  - **Test stage** — Start postgres + backend containers, run smoke tests (curl health/data). Why we test in the pipeline (catch breaks before they hit production).
  - **Push stage** — Configure AWS credentials, login to ECR, tag with SHA + latest (why SHA tags — immutability, traceability), push. Explain the needs: dependency between stages.
  - **Deploy stage** — Manual approval gate (environment: production), kubectl set image. Why manual gates matter (human in the loop before prod changes).
- **GitHub Secrets setup** — Show (but don't reveal values) where to configure AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ACCOUNT_ID, KUBE_CONFIG in the GitHub UI
- **ARM64 vs x86** — Pipeline runs on GitHub's x86 runners. Images built here are for cloud deployment. Pi uses local ARM64 builds. Explain multi-arch builds (docker buildx) as a stretch goal.
- **Trigger a run** — Make a small change, push, watch the pipeline execute in the GitHub Actions tab

### Key talking points:
- CI/CD = the bridge between writing code and running it in production
- Every stage has a purpose: build (create), test (verify), push (store), deploy (release)
- Manual approval gates = safety net for production
- Secrets management = never put credentials in code

### Deliverable by end of episode:
Working GitHub Actions pipeline that builds, tests, and pushes images

---

## Episode 9: Monitoring with Prometheus & Grafana

**Title:** "Observability — Metrics, Dashboards, and Knowing What's Happening"
**Runtime target:** 30 min

### What to cover:
- **Why monitoring?** — "Your app is running. How do you know it's healthy? How do you know it's slow? How do you know before your users complain?" The three pillars: metrics, logs, traces.
- **The /metrics endpoint** — Show what the backend serves at /metrics. Walk through the Prometheus format (counters, histograms, labels). Show the prometheus_client code in app.py.
- **Prometheus** — What it is (time-series database that scrapes endpoints):
  - Install with Helm (walk through the commands)
  - Walk through prometheus-config.yaml (scrape config, targets, intervals)
  - Port-forward to Prometheus UI, show the targets page, show a basic query
- **Grafana** — What it is (visualization layer):
  - Install with Helm or as part of kube-prometheus-stack
  - Port-forward to Grafana UI, login (admin/admin)
  - Import our dashboard JSON (walk through the import process)
  - Walk through the 4 panels:
    - Request Rate (how busy is the API?)
    - Request Duration p95 (how slow is the slowest 5%?)
    - Error Rate (what percentage of requests are failing?)
    - Health Status (is the backend up or down?)
- **Generate some traffic** — Hit the API with a loop of curl commands, watch the dashboards update in real-time
- **The Four Golden Signals** — Latency, traffic, errors, saturation. Map our panels to these signals.
- **Production extensions** — Mention AlertManager (automated alerts), log aggregation (Fluent Bit + ELK/CloudWatch)

### Key talking points:
- Monitoring is not optional in production — it's how you know things are working
- Prometheus pulls (scrapes), it doesn't receive pushes
- The Four Golden Signals = what Google SREs monitor
- Dashboards are useless without understanding what the numbers mean

### Deliverable by end of episode:
Prometheus scraping the backend, Grafana displaying a live dashboard

---

## Episode 10: Recap, Exploration & Interview Prep

**Title:** "Putting It All Together — Demo, Destroy, and Interview Prep"
**Runtime target:** 30-35 min

### What to cover:
- **Full architecture walk-through** — Start from the browser, trace a request through every component: browser → Ingress → nginx → Flask → PostgreSQL → back again. Show each component live as you trace through.
- **Self-healing demo** — Delete a backend pod, watch Kubernetes recreate it. Delete the database pod, watch it come back with data intact (PVC). Show the readiness probe keeping traffic away until the new pod is ready.
- **Scaling demo** — Scale backend to 4 replicas, show all pods running, scale back to 2. Discuss when you'd scale (load-based with HPA in production).
- **Log exploration** — `kubectl logs -f` on the backend while making requests. Show how logs correlate to requests. Mention production log aggregation.
- **Resource usage** — `kubectl top pods` to show CPU/memory consumption. Discuss how you'd right-size limits based on this data.
- **The interview walkthrough** — Practice the narrative:
  > "I built a three-tier web application from scratch — nginx frontend, Flask API, PostgreSQL database. I provisioned the cloud infrastructure with Terraform — VPC, subnets, security groups, ECR. I containerised everything with Docker and wrote a Compose file for local dev. I deployed to Kubernetes with StatefulSets, Deployments, Ingress, and NetworkPolicies. I built a CI/CD pipeline in GitHub Actions. And I added Prometheus metrics and Grafana dashboards for observability."
- **Production vs learning** — Walk through the table: managed DB, TLS, HPA, external secrets, proper CI/CD, multi-environment. What would change and why.
- **Cleanup** — Live demo of teardown:
  - `kubectl delete namespace multi-tier-app`
  - `terraform destroy` (with confirmation)
  - `docker-compose down -v`
  - Docker image cleanup
- **Series wrap-up** — Recap what was built across all episodes, encourage viewers to build it themselves, link to the GitHub repo

### Key talking points:
- The ability to trace a request through every layer = deep understanding
- Self-healing is Kubernetes' killer feature — demo it confidently
- The interview narrative should be natural, not rehearsed — understand each layer so you can answer follow-up questions
- Always clean up cloud resources — surprise bills are real

### Deliverable by end of episode:
Complete understanding of the entire stack, clean environment, interview-ready narrative

---

## Series Summary

| # | Title | Focus | Runtime |
|---|-------|-------|---------|
| 0 | What We're Building and Why It Matters | Overview, architecture, environment setup | ~30 min |
| 1 | Provisioning Cloud Infrastructure with Terraform | VPC, ECR, security groups, terraform apply | ~30 min |
| 2 | Containerising a Python API with Docker | Flask app, Dockerfile, build & test | ~30 min |
| 3 | Static Hosting and Reverse Proxying with nginx | nginx config, HTML, Dockerfile, build & test | ~30 min |
| 4 | Running the Full Stack Locally with Docker Compose | docker-compose, local dev workflow | ~25 min |
| 5 | Deploying PostgreSQL on Kubernetes with Persistent Storage | Namespace, Secret, StatefulSet, PVC, verify | ~30 min |
| 6 | Deploying the Backend and Frontend to Kubernetes | Deployments, Services, ConfigMaps, probes | ~30 min |
| 7 | Ingress Routing, Network Security, and Going Live | Ingress, NetworkPolicy, deploy script, go live | ~30 min |
| 8 | Automating Build, Test, and Deploy with GitHub Actions | CI/CD pipeline, secrets, stages, demo | ~30 min |
| 9 | Observability — Metrics, Dashboards, and Knowing What's Happening | Prometheus, Grafana, /metrics, dashboards | ~30 min |
| 10 | Putting It All Together — Demo, Destroy, and Interview Prep | Full demo, self-healing, scaling, interview narrative, cleanup | ~30 min |

**Total: 11 episodes, ~5.5 hours of content**

## Recording Tips

- **Show your terminal and browser side by side** where possible — viewers learn more when they see the cause (command) and effect (result) together
- **Make mistakes on purpose occasionally** — and show how to debug them. The troubleshooting is where the real learning happens.
- **Pause after each `kubectl apply`** — show the result with `kubectl get` before moving on. Don't rush past verification steps.
- **Keep a browser tab open on the running app** during K8s episodes — viewers can see the health badge update as you deploy/break/fix things
- **End each episode with a "What we built today" summary** and a "Next time we'll..." teaser for the next episode
