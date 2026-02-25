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

# Copy the fault injection script
COPY inject-faults.sh /opt/inject-faults.sh
RUN chmod +x /opt/inject-faults.sh

# Run fault injection then keep container alive
CMD ["/bin/bash", "-c", "/opt/inject-faults.sh && tail -f /dev/null"]
