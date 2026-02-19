#!/bin/bash
# =============================================================================
# Fault Injection: Cron Not Running
# Introduces multiple cron-related faults
# =============================================================================

# Create the backup script (this works fine when run manually)
mkdir -p /opt/scripts /var/backups
cat > /opt/scripts/backup.sh << 'BKEOF'
#!/bin/bash
echo "-- Database backup $(date)" > /var/backups/db-backup.sql
echo "-- Backup completed successfully" >> /var/backups/db-backup.sql
BKEOF

# Fault 1: Script not executable
chmod 644 /opt/scripts/backup.sh

# Fault 2: Create a broken crontab entry (invalid syntax)
# Using 6 fields instead of 5 (common mistake)
echo "0 2 * * * 0 /opt/scripts/backup.sh" | crontab -

# Fault 3: Cron daemon not running
# (In Docker, cron doesn't autostart)
# We explicitly do NOT start cron

echo "Cron faults injected."
