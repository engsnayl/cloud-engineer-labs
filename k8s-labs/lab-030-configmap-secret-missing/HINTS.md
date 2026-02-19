# Hints — Lab 030: ConfigMap and Secret Missing

## Hint 1 — Check what's needed
`kubectl describe pod -l app=webapp` shows the error events. It tells you exactly which ConfigMap/Secret and which keys are missing.

## Hint 2 — Create the ConfigMap
`kubectl create configmap app-config --from-literal=database_host=db.internal.svc.cluster.local --from-literal=database_port=5432`

## Hint 3 — Create the Secret
`kubectl create secret generic app-secrets --from-literal=db-password=supersecretpassword`
