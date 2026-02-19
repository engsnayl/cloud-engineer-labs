#!/bin/bash
# =============================================================================
# Fault Injection: Process Eating CPU
# Launches a rogue process that consumes all CPU
# =============================================================================

# Start a legitimate "application" that should keep running
cat > /opt/app.py << 'PYEOF'
import time
while True:
    time.sleep(60)
PYEOF
python3 /opt/app.py &

# Fault: Launch a CPU-eating process disguised as something innocent
# Renamed to look like a legitimate process
cp /usr/bin/stress-ng /usr/local/bin/analytics-worker
/usr/local/bin/analytics-worker --cpu 2 --timeout 0 &

echo "Process faults injected."
