#!/bin/bash
# =============================================================================
# Fault Injection: User Permissions Broken
# Introduces permission issues for a non-root application user
# =============================================================================

# Create the application user and group
groupadd appgroup
useradd -m -s /bin/bash appuser

# Create the data directory and config
mkdir -p /opt/data /etc/app

cat > /etc/app/config.yml << 'EOF'
database:
  host: db.internal
  port: 5432
  name: payments
reconciliation:
  schedule: "0 * * * *"
  output_dir: /opt/data
EOF

# Fault 1: Data directory owned by root with no group write
chown root:root /opt/data
chmod 755 /opt/data

# Fault 2: Config file has no read permission for others
chown root:root /etc/app/config.yml
chmod 600 /etc/app/config.yml

# Fault 3: appuser is NOT in appgroup
# (deliberately skip: usermod -aG appgroup appuser)

echo "Permission faults injected."
