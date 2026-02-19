# Hints — Lab 027: Ingress Misconfigured

## Hint 1 — Compare service names
`kubectl get svc` shows actual service names. `kubectl get ingress app-ingress -o yaml` shows what the ingress references. Do they match?

## Hint 2 — The ingress references a non-existent service
The root path points to 'web-frontend' but the actual service is called 'frontend'. The API port should be 80, not 3000.

## Hint 3 — Fix and apply
Edit the ingress YAML to match the actual service names and ports, then `kubectl apply -f ingress.yaml`.
