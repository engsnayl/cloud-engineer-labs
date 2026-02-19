# Hints — Lab 025: Pod CrashLoopBackOff

## Hint 1 — Describe and Logs
`kubectl describe pod -l app=payment-service` shows events and reasons. `kubectl logs -l app=payment-service --previous` shows logs from the last crash.

## Hint 2 — Three issues to find
1. The image tag `nginx:1.99.0` doesn't exist — use a real tag like `nginx:1.25`. 2. The liveness probe checks port 8080 but nginx listens on 80. 3. Resource requests are higher than limits (requests must be <= limits).

## Hint 3 — Apply the fix
Edit the deployment: `kubectl edit deployment payment-service` or fix the YAML and `kubectl apply -f deployment.yaml`.
