FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install useful debugging tools
RUN apt-get update && apt-get install -y \
    coreutils \
    findutils \
    procps \
    vim \
    less \
    lsof \
    && rm -rf /var/lib/apt/lists/*

# Create the application directory structure
RUN mkdir -p /var/lib/myapp/data \
    && mkdir -p /var/log/myapp \
    && mkdir -p /opt/backups \
    && mkdir -p /tmp/reports \
    && echo "App is healthy" > /var/lib/myapp/status.txt

# Copy the fault injection script
COPY inject-faults.sh /opt/inject-faults.sh
RUN chmod +x /opt/inject-faults.sh

# Run fault injection then keep container alive
CMD ["/bin/bash", "-c", "/opt/inject-faults.sh && tail -f /dev/null"]
