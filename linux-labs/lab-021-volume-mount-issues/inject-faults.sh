#!/bin/bash
# =============================================================================
# Fault Injection: Volume Mount Issues
# =============================================================================

# Create a volume with data in it (simulating the "lost" data)
docker volume create db-data 2>/dev/null || true
docker run --rm -v db-data:/data alpine sh -c "echo 'customer_id,name,email
1,Alice,alice@example.com
2,Bob,bob@example.com
3,Charlie,charlie@example.com' > /data/customers.db" 2>/dev/null || true

# Fault: Start the database container WITHOUT mounting the volume
docker rm -f database 2>/dev/null || true
docker run -d --name database \
    python:3.11-slim python3 -c "
import time, os
os.makedirs('/data', exist_ok=True)
while True:
    time.sleep(60)
"

echo "Volume mount faults injected."
echo "The database container is running WITHOUT its data volume."
echo "The data exists in a Docker volume called 'db-data' but is not mounted."
