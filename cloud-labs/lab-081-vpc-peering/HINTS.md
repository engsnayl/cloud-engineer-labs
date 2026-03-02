# Hints — Cloud Lab 022: VPC Peering

## Hint 1 — CIDRs can't overlap
VPC peering requires non-overlapping CIDR blocks. Change the DB VPC to something like 10.1.0.0/16.

## Hint 2 — Routes are needed on both sides
Add routes in both route tables pointing the peer VPC's CIDR to the peering connection: `route { cidr_block = "10.1.0.0/16"; vpc_peering_connection_id = ... }`

## Hint 3 — Security group CIDRs
After changing the DB VPC CIDR, update the security group ingress rule to reference the correct CIDR for the app VPC.
