# Solution Walkthrough: Part 5 — Observability

## What Is Observability?

Observability is about being able to understand what's happening inside your application **without** having to SSH into pods and read logs manually. In cloud engineering, you typically care about three pillars:

| Pillar | What It Is | Example |
|--------|-----------|---------|
| **Metrics** | Numerical measurements over time | "How many requests per second?" |
| **Logs** | Timestamped event records | "Error: database connection refused at 10:32:15" |
| **Traces** | Request journey across services | "This request took 200ms: 5ms in nginx, 50ms in Flask, 145ms in PostgreSQL" |

This project implements a **simplified metrics** endpoint. In production, you'd use dedicated tools (see below).

## What We Built

### The /metrics Endpoint

In `app.py`, we track basic request counts:

```python
request_count = {
    "health": 0,
    "data_get": 0,
    "data_post": 0,
}
```

Each endpoint increments its counter when called:
```python
@app.route("/api/health", methods=["GET"])
def health():
    request_count["health"] += 1
    # ... rest of handler
```

The `/metrics` endpoint exposes these counts:
```bash
curl http://localhost:5000/metrics
# Returns: {"requests": {"health": 42, "data_get": 15, "data_post": 3}, "status": "serving"}
```

### Limitations of This Approach

Our implementation is simplified for learning. In reality:

| Our Version | Production Version |
|------------|-------------------|
| Counts reset when pod restarts | Metrics persist in a time-series database |
| Only request counts | Latency histograms, error rates, saturation |
| Custom JSON format | Prometheus exposition format (standardized) |
| No visualization | Grafana dashboards with alerts |
| Single-pod counters | Aggregated across all replicas |

## How Production Monitoring Works

### The Prometheus + Grafana Stack

This is the industry-standard monitoring stack for Kubernetes:

```
┌────────────┐     scrapes /metrics     ┌────────────────┐
│  Your App  │◄─────────────────────────│   Prometheus   │
│ (Flask)    │    every 15 seconds      │  (time-series  │
│            │                          │   database)    │
└────────────┘                          └───────┬────────┘
                                                │
                                          queries│
                                                │
                                        ┌───────▼────────┐
                                        │    Grafana      │
                                        │  (dashboards    │
                                        │   + alerts)     │
                                        └────────────────┘
```

**How it works:**
1. Your app exposes a `/metrics` endpoint in Prometheus format
2. Prometheus **scrapes** (pulls) that endpoint at regular intervals
3. Prometheus stores the data in its time-series database
4. Grafana queries Prometheus and renders dashboards and alerts

### What Prometheus Format Looks Like

If we used the `prometheus_client` Python library, our `/metrics` endpoint would output:

```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/api/health"} 42
http_requests_total{method="GET",endpoint="/api/data"} 15
http_requests_total{method="POST",endpoint="/api/data"} 3

# HELP http_request_duration_seconds HTTP request latency
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{le="0.01"} 38
http_request_duration_seconds_bucket{le="0.05"} 52
http_request_duration_seconds_bucket{le="0.1"} 58
```

This is a plain-text format that Prometheus knows how to parse. Each line is a metric with optional labels (the `{key="value"}` parts).

## Health Probes vs Metrics

These serve different purposes:

| Feature | Health Probes | Metrics |
|---------|-------------|---------|
| **Purpose** | "Is this pod alive?" | "How is this pod performing?" |
| **Who checks** | Kubernetes kubelet | Prometheus (external) |
| **Frequency** | Every 10-20 seconds | Every 15-60 seconds |
| **On failure** | Pod restarted or removed from service | Alert sent to on-call engineer |
| **Data stored** | No (just pass/fail) | Yes (time-series history) |

Health probes are **reactive** (Kubernetes auto-heals), while metrics are **proactive** (humans spot trends before they become outages).

## The Four Golden Signals

Google's SRE (Site Reliability Engineering) book recommends monitoring these four signals for any service:

| Signal | Question | Example Metric |
|--------|----------|---------------|
| **Latency** | How long do requests take? | 95th percentile response time |
| **Traffic** | How many requests are we handling? | Requests per second |
| **Errors** | How many requests are failing? | Error rate (5xx responses / total) |
| **Saturation** | How "full" is the service? | CPU usage, memory usage, queue depth |

Our simplified `/metrics` endpoint only covers **Traffic** (request counts). A production setup would cover all four.

## Adding Prometheus to This Project (Optional Extension)

If you want to extend this project with real Prometheus monitoring:

### Step 1: Add the Python library

In `requirements.txt`:
```
prometheus_client>=0.19.0
```

### Step 2: Instrument the Flask app

```python
from prometheus_client import Counter, Histogram, generate_latest

REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['endpoint']
)

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {'Content-Type': 'text/plain'}
```

### Step 3: Install Prometheus in the cluster

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### Step 4: Add a ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-monitor
  namespace: multi-tier-app
spec:
  selector:
    matchLabels:
      app: backend
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

This tells Prometheus to scrape our backend's `/metrics` endpoint every 15 seconds.

## Key Takeaway

Observability isn't optional in production — it's how you know your system is working, catch problems early, and debug issues when they happen. Starting with a simple `/metrics` endpoint (like we did) is a valid first step. The important thing is to **expose data** that monitoring tools can consume, rather than relying on SSH and manual log reading.
