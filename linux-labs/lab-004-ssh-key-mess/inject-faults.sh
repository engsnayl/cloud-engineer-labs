#!/bin/bash
# =============================================================================
# Fault Injection: SSH Key Mess
# Introduces multiple SSH authentication faults
# =============================================================================

# Create a deploy user
useradd -m -s /bin/bash deploy

# Set up SSH directory structure 
mkdir -p /home/deploy/.ssh

chmod 777 /home/deploy/.ssh

ssh-keygen -t ed25519 -f /tmp/deploy_key -N "" -q
cat /tmp/deploy_key.pub > /home/deploy/.ssh/authorized_keys
chmod 644 /home/deploy/.ssh/authorized_keys

chown -R root:root /home/deploy/.ssh

sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PubkeyAuthentication yes/PubkeyAuthentication no/' /etc/ssh/sshd_config

# Store the private key so validation can test
cp /tmp/deploy_key /opt/.deploy_key
chmod 600 /opt/.deploy_key

echo "SSH faults injected."
