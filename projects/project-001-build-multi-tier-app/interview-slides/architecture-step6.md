# Architecture — Step 6 (compose world)

The same three-tier application, but now wired together by docker-compose.
Manual flags (`--add-host`, `--network host`) are gone. Service-name DNS handles everything.

```mermaid
flowchart TB
    classDef browser fill:#4A6B8A,stroke:#344E6B,color:#fff
    classDef pi      fill:#6B7A5E,stroke:#4A5544,color:#fff
    classDef fe      fill:#5B8A8F,stroke:#3E6A6F,color:#fff
    classDef be      fill:#2C5F2D,stroke:#1F4520,color:#fff
    classDef db      fill:#C8901E,stroke:#8F6612,color:#fff
    classDef volume  fill:#F2B544,stroke:#C8901E,color:#1A2F1B
    classDef dns     fill:#C8901E,stroke:#8F6612,color:#fff
    classDef network fill:#F4F1EA,stroke:#6B7A5E,color:#1A2F1B,stroke-dasharray:5 5

    Browser["💻 Browser / curl<br/>your laptop"]:::browser

    subgraph PiHost["🖥️ Raspberry Pi (the host)"]
        direction TB
        Pi8080["host :8080<br/>(only port published)"]:::pi

        subgraph ComposeNet["🌐 solution_default network — 172.18.0.0/16"]
            direction LR

            DNS["compose DNS<br/>127.0.0.11<br/>auto-injected"]:::dns

            subgraph FrontendContainer["📦 frontend"]
                Nginx["nginx<br/>listens :8080<br/>serves index.html<br/>proxies /api/<br/>→ backend:5000"]:::fe
            end

            subgraph BackendContainer["📦 backend"]
                Flask["Flask app<br/>listens :5000<br/>connects to<br/>database:5432"]:::be
            end

            subgraph DatabaseContainer["📦 database"]
                Postgres["Postgres 15<br/>listens :5432<br/>(internal only)"]:::db
            end
        end

        PgData[("💾 postgres-data<br/>named volume<br/>persists data")]:::volume
    end

    Browser -- "HTTP :8080" --> Pi8080
    Pi8080 -- "published port" --> Nginx
    Nginx -. "resolves 'backend'<br/>via DNS" .-> DNS
    DNS -. "→ 172.18.0.3" .-> Flask
    Flask -. "resolves 'database'<br/>via DNS" .-> DNS
    DNS -. "→ 172.18.0.2" .-> Postgres
    Postgres -. "stores data in" .-> PgData
```

## What changed from Step 5

| Step 5 (manual) | Step 6 (compose) |
|---|---|
| `--add-host=backend:host-gateway` on frontend | Service name `backend` resolves via compose DNS |
| `--network host` on backend | Joins the `solution_default` network like every other service |
| `-p 5432:5432` on postgres (exposed externally) | Internal only — never published, never reachable from outside |
| `-p 5000:5000` on backend (exposed externally) | Internal only |
| Three separate `docker run` commands | One `docker compose up` |
| Manual ordering / sleeps | `depends_on` with healthcheck conditions |
| No data persistence guarantee | Named volume `postgres-data` survives container removal |

The cleanest observation: **only one port published to the outside world.** The Pi exposes 8080 (nginx) and nothing else. Backend and database are reachable only from within the compose network. That's a security improvement that came for free.
