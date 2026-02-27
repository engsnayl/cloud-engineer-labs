# Hints — NAT Gateway & VPC Endpoints

## Hint 1
A NAT Gateway must be placed in a PUBLIC subnet (one with a route to an Internet Gateway). It translates private IPs to public IPs — it needs internet access itself to do this.

## Hint 2
Private subnets route to the NAT Gateway, not directly to the Internet Gateway. Check what the 0.0.0.0/0 route points to.

## Hint 3
A VPC Endpoint for S3 needs to be associated with the route table of the subnet that needs S3 access.

## Hint 4
VPC Endpoint policies work like IAM policies. Check the Effect — is it Allow or Deny?
