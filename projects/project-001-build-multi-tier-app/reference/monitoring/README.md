# Monitoring Stack: Prometheus + Grafana

This directory contains the configuration for monitoring the multi-tier application
using Prometheus (metrics collection) and Grafana (visualization).

## What Does Prometheus Do?

Prometheus is a monitoring system that **scrapes** (fetches) metrics from your
application on a regular interval. Your backend exposes a `/metrics` endpoint
that returns data like request counts, response times, and error counts.
Prometheus visits this endpoint every 15 seconds and stores the data.

Think of it as a thermometer that checks your app's temperature every 15 seconds
and writes it down in a log book.

**Key file:** `prometheus-config.yaml` -- Kubernetes ConfigMap that tells Prometheus
what to scrape and how often.

## What Does Grafana Do?

Grafana is a visualization tool that connects to Prometheus and turns raw numbers
into graphs, charts, and dashboards. Prometheus collects the data; Grafana makes
it visual and understandable.

**Key file:** `grafana-dashboard.json` -- A pre-built dashboard with 4 panels.

## Installing Prometheus and Grafana

The easiest way is using the `kube-prometheus-stack` Helm chart, which installs
Prometheus, Grafana, and a bunch of useful defaults in one command:

```bash
# Step 1: Add the Helm chart repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Step 2: Install the monitoring stack
# This creates a "monitoring" namespace and installs everything there.
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Step 3: Verify everything is running
kubectl get pods -n monitoring
# You should see pods for prometheus, grafana, alertmanager, etc.
```

## Accessing Prometheus

Prometheus has a web UI where you can run queries and see what targets are being scraped.

```bash
# Forward the Prometheus port to your local machine
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Then open [http://localhost:9090](http://localhost:9090) in your browser.

Try these queries:
- `up` -- shows which targets are alive (1) or down (0)
- `http_requests_total` -- total number of requests (a counter)
- `rate(http_requests_total[5m])` -- requests per second over the last 5 minutes

## Accessing Grafana

```bash
# Forward the Grafana port to your local machine
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Then open [http://localhost:3000](http://localhost:3000) in your browser.

Default credentials (from the Helm chart):
- **Username:** admin
- **Password:** prom-operator

## Importing the Dashboard

The file `grafana-dashboard.json` contains a pre-built dashboard. To import it:

1. Open Grafana at [http://localhost:3000](http://localhost:3000)
2. Click the **"+"** icon in the left sidebar (or go to Dashboards)
3. Click **"Import"**
4. Click **"Upload JSON file"** and select `grafana-dashboard.json`
   (or copy-paste the file contents into the text box)
5. Select **"Prometheus"** as the datasource when prompted
6. Click **"Import"**

The dashboard should appear with 4 panels.

## What the 4 Dashboard Panels Show

| Panel | Metric | What It Tells You |
|-------|--------|-------------------|
| **Request Rate** | `rate(http_requests_total[5m])` | How many requests per second the backend is handling, broken down by endpoint and HTTP method. Spikes here mean more traffic. |
| **Request Duration (p95)** | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` | 95% of requests complete faster than this value. If p95 is 0.5s, only 5% of requests take longer than half a second. Watch for this creeping up -- it means your app is getting slower. |
| **Error Rate (5xx)** | `rate(5xx) / rate(total) * 100` | What percentage of requests are failing with server errors. Should be near 0% in a healthy system. Spikes here mean something is broken. |
| **Health Status** | `up{job="backend"}` | Is the backend alive? Shows UP (green) or DOWN (red). This is the most basic check -- if this is red, nothing else matters until you fix it. |

## Applying the Prometheus Config

If you are running Prometheus outside of the Helm stack (or want to add custom
scrape targets), apply the ConfigMap:

```bash
# Create the monitoring namespace if it doesn't exist
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Apply the Prometheus config
kubectl apply -f prometheus-config.yaml
```

Note: If you used the `kube-prometheus-stack` Helm chart, it manages its own
Prometheus config. You would add custom scrape configs via Helm values instead.
See the comments in `prometheus-config.yaml` for details.
