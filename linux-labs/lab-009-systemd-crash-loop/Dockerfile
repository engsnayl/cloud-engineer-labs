FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    systemctl vim less procps python3 curl net-tools \
    && rm -rf /var/lib/apt/lists/*

COPY inject-faults.sh /opt/inject-faults.sh
RUN chmod +x /opt/inject-faults.sh

# Run fault injection during build so faults are baked in for systemd
RUN /opt/inject-faults.sh

CMD ["/sbin/init"]
