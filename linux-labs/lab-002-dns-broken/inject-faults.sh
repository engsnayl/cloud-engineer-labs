#!/bin/bash
# =============================================================================
# Fault Injection: DNS Broken
# Introduces multiple DNS-related faults
# =============================================================================

# Save the real resolv.conf so validation can work within Docker networking
REAL_NS=$(grep nameserver /etc/resolv.conf | head -1)

# Fault 1: Corrupt resolv.conf with invalid nameservers
cat > /etc/resolv.conf << 'EOF'
# Updated during maintenance window - network team
nameserver 192.168.999.1
nameserver 10.255.255.254
search localdomain
EOF

# Fault 2: Remove the hosts entry that the app depends on
# (It should have payments-api.internal -> 10.0.1.50)
# We'll add a WRONG entry to make it trickier
echo "10.0.99.99  payments-api.internal" >> /etc/hosts

# Fault 3: Set a restrictive nsswitch.conf that skips DNS
# Change 'hosts: files dns' to 'hosts: files' so it never queries DNS
if [[ -f /etc/nsswitch.conf ]]; then
    sed -i 's/^hosts:.*/hosts:          files/' /etc/nsswitch.conf
fi

# Store the real nameserver in a hidden file for the validation script
echo "$REAL_NS" > /opt/.real-ns

echo "DNS faults injected."
