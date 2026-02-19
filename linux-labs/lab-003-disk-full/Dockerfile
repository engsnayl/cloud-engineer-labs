FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    vim \
    less \
    procps \
    logrotate \
    cron \
    findutils \
    && rm -rf /var/lib/apt/lists/*

# Create app directory structure
RUN mkdir -p /var/log/myapp /opt/myapp /var/cache/myapp /tmp/reports

COPY inject-faults.sh /opt/inject-faults.sh
COPY fake-app.sh /opt/myapp/fake-app.sh
RUN chmod +x /opt/inject-faults.sh /opt/myapp/fake-app.sh

CMD ["/bin/bash", "-c", "/opt/inject-faults.sh && tail -f /dev/null"]
