#!/bin/bash
# =============================================================================
# Fault Injection: Swap and Memory Pressure
# Disables swap and creates a memory-leaking process
# =============================================================================

# Create a swap file but don't enable it
dd if=/dev/zero of=/swapfile bs=1M count=256 2>/dev/null
chmod 600 /swapfile
mkswap /swapfile >/dev/null 2>&1

# Start a legitimate application
cat > /opt/app.py << 'PYEOF'
import time
while True:
    time.sleep(60)
PYEOF
python3 /opt/app.py &

python3 -c "
import time
data = []
while True:
    data.append('X' * 1024 * 100)  # Grow by 100KB each iteration
    time.sleep(0.5)
" &

echo "Memory faults injected."
