# Solution Walkthrough: Part 0 — Architecture Overview

## The Big Picture

We're building a classic **three-tier architecture** — the same pattern used by the majority of web applications in the real world. Understanding this pattern is foundational to cloud engineering.

### What Are the Three Tiers?

```
┌──────────────────────────────────────────────────────┐
│                 TIER 1: PRESENTATION                  │
│                                                       │
│  What the user sees. In our case, an nginx web server │
│  that serves HTML pages and forwards API calls.       │
│  This tier has NO business logic — it just displays.  │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│                  TIER 2: APPLICATION                  │
│                                                       │
│  The "brains" of the app. Our Flask API handles       │
│  business logic — processing requests, validating     │
│  data, and deciding what to read/write to the DB.     │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│                    TIER 3: DATA                       │
│                                                       │
│  Where data lives permanently. Our PostgreSQL         │
│  database stores items that persist even if every     │
│  other component restarts.                            │
└──────────────────────────────────────────────────────┘
```

### Why Separate Into Tiers?

You *could* put everything in one container — serve HTML, handle API calls, and store data all in the same process. But splitting into tiers gives you:

1. **Independent scaling** — If the API is slow but the database is fine, you can add more API pods without touching anything else
2. **Independent deployment** — Push a frontend update without restarting the database
3. **Security boundaries** — The frontend never touches the database directly; the NetworkPolicy enforces this
4. **Team autonomy** — A frontend developer and a backend developer can work in parallel without stepping on each other

## Build Order: Bottom Up

We build from the bottom of the stack upward:

```
Step 1: Namespace      → The "room" everything lives in
Step 2: Database       → Has no dependencies, so build it first
Step 3: Backend        → Depends on the database
Step 4: Frontend       → Depends on the backend
Step 5: Networking     → Ties everything together with Ingress + policies
```

This order matters because each layer depends on the one below it. If you tried to deploy the backend before the database exists, the health checks would fail and Kubernetes would keep restarting the backend pods.

## Kubernetes Concepts Used

Here's every Kubernetes concept we use in this project, and where:

| Concept | What It Does | Where We Use It |
|---------|-------------|----------------|
| **Namespace** | Isolates resources into a group | `namespace.yaml` — all resources go in `multi-tier-app` |
| **Deployment** | Runs and manages stateless pods | Frontend (2 replicas) and Backend (2 replicas) |
| **StatefulSet** | Runs pods with stable identity + storage | PostgreSQL (1 replica with persistent disk) |
| **Service** | Stable network endpoint for pods | One per tier (frontend, backend, postgres) |
| **ConfigMap** | Stores non-sensitive configuration | DB init script, backend connection settings |
| **Secret** | Stores sensitive data (passwords) | Database credentials |
| **Ingress** | Routes external traffic into the cluster | Path-based routing: `/` and `/api/*` |
| **NetworkPolicy** | Firewall rules between pods | Only backend can talk to database |
| **PersistentVolumeClaim** | Requests persistent disk storage | 1Gi disk for PostgreSQL data |

## How Requests Flow

When a user opens the app in their browser:

```
1. Browser requests "http://my-app/"
   └─► Ingress sees path "/" → routes to Frontend Service

2. Frontend Service picks a frontend pod (nginx)
   └─► nginx serves index.html back to the browser

3. Browser's JavaScript calls "fetch('/api/health')"
   └─► Request goes to nginx (same origin)
   └─► nginx sees "/api/" → proxy_pass to http://backend:5000
   └─► Backend Service picks a backend pod (Flask)
   └─► Flask connects to PostgreSQL via "postgres:5432" Service
   └─► Response flows back: Flask → nginx → Browser
```

## Walkthrough Navigation

Each subsequent SOLUTION document covers one layer in detail:

- **[SOLUTION-01-DATABASE.md](SOLUTION-01-DATABASE.md)** — PostgreSQL StatefulSet, Secret, init script
- **[SOLUTION-02-BACKEND.md](SOLUTION-02-BACKEND.md)** — Flask app, Dockerfile, Deployment, ConfigMap
- **[SOLUTION-03-FRONTEND.md](SOLUTION-03-FRONTEND.md)** — nginx, static HTML, Dockerfile, Deployment
- **[SOLUTION-04-NETWORKING.md](SOLUTION-04-NETWORKING.md)** — Ingress routing, NetworkPolicy security
- **[SOLUTION-05-OBSERVABILITY.md](SOLUTION-05-OBSERVABILITY.md)** — Metrics endpoint, monitoring concepts
