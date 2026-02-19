# Hints — Lab 026: Service Discovery Broken

## Hint 1 — Compare labels
`kubectl get pods --show-labels` shows pod labels. `kubectl get svc backend-api -o yaml` shows the service selector. Do they match?

## Hint 2 — Two mismatches
The service selector says `app: backend` but pods have `app: backend-api`. The selector says `tier: api` but pods have `tier: backend`. Both must match exactly.

## Hint 3 — Also check the port
The targetPort in the service (8080) doesn't match the containerPort (80). Fix the service YAML and reapply.
