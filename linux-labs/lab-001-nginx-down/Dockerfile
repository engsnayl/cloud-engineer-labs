FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install nginx and useful debugging tools
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    vim \
    less \
    net-tools \
    procps \
    systemctl \
    && rm -rf /var/lib/apt/lists/*

# Create a simple default page so we know when it's working
RUN echo '<!DOCTYPE html><html><body><h1>Portal is UP</h1></body></html>' > /var/www/html/index.html

# Copy the fault injection script
COPY inject-faults.sh /opt/inject-faults.sh
RUN chmod +x /opt/inject-faults.sh

# Run fault injection then keep container alive
CMD ["/bin/bash", "-c", "/opt/inject-faults.sh && tail -f /dev/null"]
