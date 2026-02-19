FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 curl vim less procps pip \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY inject-faults.sh /opt/inject-faults.sh
RUN chmod +x /opt/inject-faults.sh

CMD ["/bin/bash", "-c", "/opt/inject-faults.sh && tail -f /dev/null"]
