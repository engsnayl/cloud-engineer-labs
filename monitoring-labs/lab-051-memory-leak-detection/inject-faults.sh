#!/bin/bash
python3 -c "
import time
while True:
    time.sleep(60)
" &
echo $! > /tmp/legit-app.pid

python3 -c "
import time
cache = {}
counter = 0
while True:
    cache[f'session_{counter}'] = 'x' * 10240
    counter += 1
    time.sleep(0.2)
" &
echo $! > /tmp/leaky.pid

mkdir -p /var/log/monitoring
cat > /opt/collect-metrics.sh << 'SCRIPT'
#!/bin/bash
while true; do
    echo "$(date +%H:%M:%S) $(free -m | grep Mem | awk '{print $3}')" >> /var/log/monitoring/memory.log
    sleep 5
done
SCRIPT
chmod +x /opt/collect-metrics.sh
/opt/collect-metrics.sh &

echo "Lab environment ready."
