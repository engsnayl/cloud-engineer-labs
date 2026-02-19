#!/bin/bash
# =============================================================================
# Fault Injection: Filesystem Mount Failed
# Creates a volume with bad fstab entry
# =============================================================================

# Create a loopback device to simulate a data volume
mkdir -p /data
dd if=/dev/zero of=/opt/fake-volume.img bs=1M count=50 2>/dev/null
mkfs.ext4 -q /opt/fake-volume.img

# Mount it temporarily to add data files
mount -o loop /opt/fake-volume.img /data
echo "database_dir = /data/pgdata" > /data/db-data.conf
mkdir -p /data/pgdata
echo "PostgreSQL data lives here" > /data/pgdata/PG_VERSION
umount /data

# Fault 1: Wrong device path in fstab
echo "/dev/sdb1    /data    ext4    defaults    0    2" >> /etc/fstab
# The actual device is a loop device from /opt/fake-volume.img, not /dev/sdb1

# Fault 2: The mount point exists but is empty (confusing — looks like data loss)

echo "Filesystem mount faults injected."
