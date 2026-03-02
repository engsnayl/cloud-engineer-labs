# Hints — Cloud Lab 007: RDS Connectivity

## Hint 1 — Security group CIDR
The DB security group allows traffic from 10.0.99.0/24 but the app is in 10.0.1.0/24. Better practice: reference the app security group ID instead of a CIDR.

## Hint 2 — Best practice for SG references
Use `security_groups = [aws_security_group.app.id]` instead of CIDR blocks. This way if the app moves subnets, the rule still works.

## Hint 3 — RDS should not be publicly accessible
Set `publicly_accessible = false` — RDS in a private subnet should not be reachable from the internet.
