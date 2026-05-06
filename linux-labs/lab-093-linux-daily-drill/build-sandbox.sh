#!/usr/bin/env bash
# build-sandbox.sh — populates a fresh sandbox directory with all files the
# drill scenarios expect. Called automatically by drill.py on each run.

set -euo pipefail

SANDBOX="${1:-./sandbox}"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
cd "$SANDBOX"

# ─── access.log: realistic-ish web server log ────────────────────────────────
cat > access.log <<'EOF'
192.168.1.10 - - [05/May/2026:08:01:23 +0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.11 - - [05/May/2026:08:01:24 +0000] "GET /api/health HTTP/1.1" 200 18
192.168.1.12 - - [05/May/2026:08:01:25 +0000] "POST /api/login HTTP/1.1" 200 256
192.168.1.13 - - [05/May/2026:08:01:26 +0000] "GET /favicon.ico HTTP/1.1" 404 0
192.168.1.14 - - [05/May/2026:08:01:27 +0000] "GET /api/users HTTP/1.1" 500 87
10.0.0.5 - - [05/May/2026:08:01:28 +0000] "GET /api/users HTTP/1.1" 200 1532
10.0.0.6 - - [05/May/2026:08:01:29 +0000] "GET /api/users HTTP/1.1" 500 87
10.0.0.7 - - [05/May/2026:08:01:30 +0000] "GET /api/orders HTTP/1.1" 200 4096
10.0.0.8 - - [05/May/2026:08:01:31 +0000] "GET /api/orders HTTP/1.1" 503 42
10.0.0.9 - - [05/May/2026:08:01:32 +0000] "GET /index.html HTTP/1.1" 200 1024
172.16.0.1 - - [05/May/2026:08:01:33 +0000] "GET /api/health HTTP/1.1" 200 18
172.16.0.2 - - [05/May/2026:08:01:34 +0000] "POST /api/login HTTP/1.1" 401 64
172.16.0.3 - - [05/May/2026:08:01:35 +0000] "GET /static/app.css HTTP/1.1" 200 8192
172.16.0.4 - - [05/May/2026:08:01:36 +0000] "GET /api/users HTTP/1.1" 500 87
172.16.0.5 - - [05/May/2026:08:01:37 +0000] "GET /api/users HTTP/1.1" 200 1532
172.16.0.6 - - [05/May/2026:08:01:38 +0000] "DELETE /api/users/42 HTTP/1.1" 204 0
192.168.1.20 - - [05/May/2026:08:01:39 +0000] "GET /api/health HTTP/1.1" 200 18
192.168.1.21 - - [05/May/2026:08:01:40 +0000] "GET /api/users HTTP/1.1" 500 87
192.168.1.22 - - [05/May/2026:08:01:41 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.23 - - [05/May/2026:08:01:42 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.24 - - [05/May/2026:08:01:43 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.25 - - [05/May/2026:08:01:44 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.26 - - [05/May/2026:08:01:45 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.27 - - [05/May/2026:08:01:46 +0000] "GET /api/products HTTP/1.1" 200 2048
192.168.1.28 - - [05/May/2026:08:01:47 +0000] "GET /api/products HTTP/1.1" 200 2048
EOF

# ─── app.log: simulates application log with errors ──────────────────────────
cat > app.log <<'EOF'
2026-05-05 08:00:00 INFO  Starting application v2.4.1
2026-05-05 08:00:01 INFO  Connected to database postgres://db.internal:5432
2026-05-05 08:00:02 INFO  Listening on 0.0.0.0:8080
2026-05-05 08:00:15 WARN  Slow query detected: 1.2s
2026-05-05 08:01:27 ERROR Database connection lost: timeout after 30s
2026-05-05 08:01:28 ERROR Failed to fetch user 42: connection refused
2026-05-05 08:01:30 INFO  Reconnected to database
2026-05-05 08:02:00 INFO  Health check OK
2026-05-05 08:03:15 ERROR Out of memory: killing worker pid=1247
2026-05-05 08:03:16 INFO  Spawned new worker pid=1289
2026-05-05 08:04:00 WARN  High memory usage: 92%
2026-05-05 08:05:00 INFO  Health check OK
EOF

# ─── config.txt: app config with localhost references ────────────────────────
cat > config.txt <<'EOF'
db_host=localhost
db_port=5432
cache_host=localhost
cache_port=6379
api_endpoint=http://localhost:8080/api
EOF

# ─── hosts.txt: deliberately unsorted with duplicates ────────────────────────
cat > hosts.txt <<'EOF'
web-02.prod
db-01.prod
web-01.prod
web-02.prod
cache-01.prod
db-01.prod
web-01.prod
EOF

# ─── big.dat: ~2MB so 'find -size +1M' has something to find ─────────────────
dd if=/dev/zero of=big.dat bs=1024 count=2048 status=none

# ─── deploy.sh: starts non-executable so chmod +x has work to do ─────────────
cat > deploy.sh <<'EOF'
#!/usr/bin/env bash
echo "Deploying..."
EOF
chmod 644 deploy.sh

# ─── sample.tar.gz: pre-made archive for the extract scenario ────────────────
echo "this is a backed-up file" > _backup_source.txt
tar -czf sample.tar.gz _backup_source.txt
rm _backup_source.txt

# ─── data.json: for jq scenarios ─────────────────────────────────────────────
cat > data.json <<'EOF'
{
  "version": "2.4.1",
  "environment": "production",
  "region": "eu-west-1",
  "users": [
    { "id": 1, "name": "alice", "role": "admin" },
    { "id": 2, "name": "bob",   "role": "developer" },
    { "id": 3, "name": "carol", "role": "viewer" }
  ],
  "services": ["api", "web", "worker"]
}
EOF

# ─── src/ directory with a few files for rsync scenario ──────────────────────
mkdir -p src
echo "file one"   > src/one.txt
echo "file two"   > src/two.txt
echo "file three" > src/three.txt
