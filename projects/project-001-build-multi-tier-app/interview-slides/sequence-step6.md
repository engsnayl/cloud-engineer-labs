# The Journey of a Request — Step 6 (compose)

Same `/api/data` request as Step 5, but the wiring underneath is now compose-managed.
No more `--add-host`. No more `--network host`. Service names just resolve.

```mermaid
sequenceDiagram
    autonumber
    actor Browser as 💻 Browser
    participant Pi as 🖥️ Raspberry Pi<br/>(host)
    participant Frontend as 📦 Frontend<br/>(nginx)
    participant DNS as 🌐 Compose DNS<br/>127.0.0.11
    participant Backend as 📦 Backend<br/>(Flask)
    participant Database as 📦 Database<br/>(Postgres)

    Browser->>Pi: GET /api/data on :8080
    Pi->>Frontend: routes to container :8080 (only published port)
    Note over Frontend: nginx matches /api/<br/>proxy_pass http://backend:5000
    Frontend->>DNS: resolve "backend"
    DNS-->>Frontend: 172.18.0.3
    Frontend->>Backend: HTTP GET to 172.18.0.3:5000
    Note over Backend: Flask receives<br/>opens psycopg2 connection
    Backend->>DNS: resolve "database"
    DNS-->>Backend: 172.18.0.2
    Backend->>Database: TCP to 172.18.0.2:5432
    Database->>Database: SELECT * FROM messages
    Database-->>Backend: 3 rows
    Note over Backend: serialises to JSON
    Backend-->>Frontend: HTTP 200 + JSON body
    Frontend-->>Browser: HTTP 200 + JSON body
```

## How this is different from Step 5

Look at the new participant: **Compose DNS at 127.0.0.11.** That's the actor doing all the wiring.

In Step 5, the equivalent role was played by:
- `--add-host=backend:host-gateway` for the frontend→backend leg
- `--network host` for the backend→database leg

Both manual. Both fragile. Compose replaces them with a single mechanism — embedded DNS that knows every service name in the network. Every container queries the same DNS server. Every service name resolves correctly. **No flags. No tricks. Just a contract.**

## The wider lesson

This pattern — *service names resolved via internal DNS* — is the same mental model used by:

- **Kubernetes Services** (where `backend.default.svc.cluster.local` is the equivalent of `backend`)
- **AWS Service Discovery** (Cloud Map)
- **Consul**, **Nomad**, **Nomad Connect**
- Every modern service mesh

What we just built in compose is a miniature version of how every real production cluster does service-to-service communication. **Module 3 will feel familiar** — the K8s equivalent is `Service` resources, and the DNS just works the same way at scale.
