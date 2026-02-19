# Hints — Lab 023: Compose Orchestration

## Hint 1 — Run it and read the errors
`cd /opt/fullstack-app && docker compose up` (without -d) shows all output. Read the errors from each service.

## Hint 2 — Four issues to fix
1. `depends_on` references 'backend' but the service is called 'api'. 2. The API needs its code mounted as a volume. 3. DB_HOST should match the service name 'db', not 'database'. 4. postgres requires POSTGRES_PASSWORD environment variable.

## Hint 3 — Volume for the API
Add `volumes: - ./app:/app` to the api service so it can find api.py.
