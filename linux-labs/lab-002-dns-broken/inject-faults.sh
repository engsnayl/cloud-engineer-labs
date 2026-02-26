#!/bin/bash
# =============================================================================
# Fault Injection: DNS Broken
# Introduces multiple DNS-related faults that prevent name resolution
# =============================================================================

# Save the real resolv.conf so validation can work within Docker networking
REAL_NS=$(grep nameserver /etc/resolv.conf | head -1)

# Fault 1: Replace resolv.conf with invalid nameservers
# One has an impossible IP (999 is not a valid octet — max is 255)
# The other is a valid-looking IP that doesn't respond
cat > /etc/resolv.conf << 'EOF'
# Updated during maintenance window — network team
nameserver 192.168.999.1
nameserver 10.255.255.254
search localdomain
EOF

# Fault 2: Break nsswitch.conf so the system skips DNS lookups entirely
# Change 'hosts: files dns' to 'hosts: files'
# This means even with a valid nameserver, normal apps won't query DNS
if [[ -f /etc/nsswitch.conf ]]; then
    sed -i 's/^hosts:.*/hosts:          files/' /etc/nsswitch.conf
fi

# Fault 3: Add a WRONG entry for the internal service in /etc/hosts
# The app expects payments-api.internal to resolve to 10.0.1.50
# This points it to a completely wrong IP
echo "10.0.99.99  payments-api.internal" >> /etc/hosts

# Store the real nameserver in a hidden file for the validation script
echo "$REAL_NS" > /opt/.real-ns

echo "DNS faults injected."
