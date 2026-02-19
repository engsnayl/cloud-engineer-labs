#!/bin/bash
# =============================================================================
# Fault Injection: Container OOM Kill
# =============================================================================

cat > /opt/run-processor.sh << 'SEOF'
#!/bin/bash
# Start a data processor with too-small memory limit
docker rm -f data-processor 2>/dev/null || true

# Fault: Memory limit too small (32MB) for the workload
docker run -d --name data-processor \
    --memory=32m \
    python:3.11-slim python3 -c "
import time
# Simulate a data processing workload that needs ~128MB
data = []
for i in range(100):
    data.append('X' * 1024 * 1024)  # 1MB chunks
    time.sleep(0.1)
print('Processing complete')
time.sleep(3600)
"
echo "Data processor started with 32MB memory limit."
echo "Watch it with: docker stats data-processor"
SEOF
chmod +x /opt/run-processor.sh

echo "OOM kill faults prepared. Run /opt/run-processor.sh to start."
