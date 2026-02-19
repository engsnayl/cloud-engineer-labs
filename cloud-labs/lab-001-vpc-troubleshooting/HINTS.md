# Hints — Cloud Lab 001: VPC Troubleshooting

## Hint 1 — Think about the NAT Gateway
A NAT Gateway needs to be in a subnet that has a route to the internet. Which subnet has the Internet Gateway route?

## Hint 2 — Follow the route
For an instance in the private subnet to reach the internet, the traffic path is: Instance → Private Route Table → NAT Gateway → Public Route Table → Internet Gateway → Internet. Check each hop in that chain. Where does the private route table actually send 0.0.0.0/0 traffic?

## Hint 3 — Security groups are deny-by-default
AWS security groups have an implicit deny. If you don't explicitly add an egress rule, nothing gets out. The Terraform `aws_security_group` resource doesn't automatically add the default "allow all outbound" rule unless you define it.

## Hint 4 — Where's the instance?
Check which subnet the instance is actually launched in. The scenario says it should be in the private subnet.
