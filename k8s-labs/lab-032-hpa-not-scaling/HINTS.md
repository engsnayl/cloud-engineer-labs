# Hints — Lab 032: HPA Not Scaling

## Hint 1 — Check HPA status
`kubectl describe hpa web-tier-hpa` shows why metrics are unknown. Look at the Conditions section.

## Hint 2 — HPA needs resource requests
The HPA calculates utilization as a percentage of resource *requests*. If no requests are set, it can't calculate a percentage. The deployment is missing resource requests.

## Hint 3 — Add resource requests
Edit the deployment to add `resources.requests.cpu: "100m"` and `resources.requests.memory: "128Mi"`. The HPA will start showing metrics after the pods restart.
