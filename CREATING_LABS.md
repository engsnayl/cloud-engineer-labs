# Creating Your Own Labs

This guide explains the patterns so you can create new labs quickly — either manually or with Claude Code's help.

## Linux Lab Template

Every Linux lab follows the same pattern:

```
linux-labs/lab-NNN-short-name/
├── CHALLENGE.md        # Scenario briefing and objectives
├── Dockerfile          # Base image + tools + fault injection
├── inject-faults.sh    # Script that breaks things
├── docker-compose.yml  # Container configuration
├── validate.sh         # Automated pass/fail checks
└── HINTS.md            # Progressive hints (optional)
```

### Step 1: Design the Fault

Start with a real incident you might encounter. Ask yourself:
- What would break in production?
- What would the symptoms look like?
- What tools would you use to diagnose it?
- Can I introduce 2-3 related faults to make it realistic?

### Step 2: Write inject-faults.sh

This script runs when the container starts and introduces the problems. Common patterns:

```bash
# Corrupt a config file
sed -i 's/valid/invalid/' /etc/some/config

# Wrong permissions
chmod 000 /some/directory

# Fill up space
dd if=/dev/urandom of=/tmp/bigfile bs=1M count=100

# Kill or misconfigure a service
echo "broken config" > /etc/service/config

# Create a process that misbehaves
while true; do cat /dev/urandom > /dev/null; done &

# Add wrong entries to key files
echo "bad.entry" >> /etc/hosts
```

### Step 3: Write validate.sh

Each check should test ONE specific thing and give a clear pass/fail:

```bash
CONTAINER="labNNN-name"

# Pattern: run a command in the container and check the result
docker exec "$CONTAINER" some_command &>/dev/null
check "Description of what this validates" "$?"
```

### Step 4: Write CHALLENGE.md

Use this header format (the lab runner parses it):

```markdown
Title: Short descriptive title
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Networking
Skills: tool1, tool2, tool3
```

## Cloud Lab Template

```
cloud-labs/lab-NNN-short-name/
├── CHALLENGE.md        # Scenario and objectives
├── main.tf             # DELIBERATELY BROKEN Terraform
├── variables.tf        # Input variables
├── validate.sh         # AWS CLI validation checks
└── HINTS.md            # Progressive hints
```

### Key Principle

The Terraform should be valid enough to `terraform apply` successfully — the bugs are LOGICAL, not syntactical. Examples:
- Resources in the wrong subnet
- Missing route table entries
- Security groups too restrictive or too permissive
- IAM roles missing permissions
- Wrong AMI or instance type for the use case

Comment each bug with `# BUG N:` so you can track them, but remove these comments if you want a harder challenge.

## Lab Ideas to Build Next

### Linux Labs
- **SSH Key Mess**: Multiple users, wrong key permissions, sshd_config locked down too hard
- **Process Eating CPU**: Runaway process, use top/htop/ps to find and kill it, investigate why
- **Cron Not Running**: Job exists but doesn't execute — permissions, path, syntax issues
- **Firewall Blocking**: iptables rules blocking legitimate traffic, need to diagnose and fix
- **User Can't Sudo**: sudoers file corrupted, user not in right group
- **SSL Certificate Expired**: Nginx won't start because cert chain is broken
- **Service Dependency**: App won't start because it depends on another service that's down
- **Log Investigation**: Something happened last night — read the logs to figure out what

### Cloud Labs
- **S3 Bucket Policy**: Overly permissive bucket that needs locking down per security audit
- **IAM Role Missing**: Lambda function can't access DynamoDB — fix the IAM policy
- **EKS Node Group**: Nodes can't join the cluster — networking/IAM issues
- **RDS Connectivity**: App can't connect to RDS — security groups, subnet groups, routing
- **CloudWatch Alarms**: Set up proper monitoring for an EC2 instance
- **Auto Scaling Broken**: ASG not scaling — check launch template, health checks, policies

## Using Claude Code to Generate Labs

You can accelerate lab creation by asking Claude Code:

> "Create a new Linux troubleshooting lab where a PostgreSQL database won't start because
> of a corrupted pg_hba.conf, wrong data directory permissions, and a port conflict with
> another service. Follow the pattern in linux-labs/lab-001-nginx-down/"

Claude Code can generate the Dockerfile, inject-faults.sh, validate.sh, and CHALLENGE.md following the established patterns in this repo.
