# Hints — Cloud Lab 006: EC2 No Internet

## Hint 1 — Four bugs to find
Trace the path: Instance → Subnet → Route Table → Gateway. Each hop has a potential issue.

## Hint 2 — NAT Gateway placement
NAT Gateways must be in a PUBLIC subnet with an IGW route. Private route tables should point to the NAT Gateway, not the IGW.

## Hint 3 — Security group egress
AWS security groups are stateful, but you still need egress rules for the initial outbound connection. Add an egress rule allowing all outbound traffic.

## Hint 4 — Instance subnet
The instance should be in the private subnet, not the public one. That's the whole point of private subnets with NAT.
