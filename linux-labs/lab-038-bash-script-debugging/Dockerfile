FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    procps \
    shellcheck \
    curl \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Create test directories and files
RUN mkdir -p /var/log/app /var/reports /opt/scripts && \
    for i in $(seq 1 30); do \
        date_str=$(date -d "-${i} days" +%Y%m%d 2>/dev/null || date +%Y%m%d); \
        echo "Log entry for day $i" > "/var/log/app/app-${date_str}.log"; \
    done && \
    echo "Log entry for today - line 1" > /var/log/app/app-current.log && \
    echo "Log entry for today - line 2" >> /var/log/app/app-current.log && \
    echo "ERROR: something failed" >> /var/log/app/app-current.log && \
    echo "Log entry for today - line 3" >> /var/log/app/app-current.log

COPY healthcheck.sh /opt/scripts/healthcheck.sh
RUN chmod +x /opt/scripts/healthcheck.sh

CMD ["sleep", "infinity"]
