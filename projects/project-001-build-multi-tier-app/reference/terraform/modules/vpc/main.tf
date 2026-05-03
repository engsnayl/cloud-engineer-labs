# =============================================================================
# FILE: modules/vpc/main.tf
# PURPOSE: Creates the Virtual Private Cloud (VPC) and all networking resources
#          needed for our multi-tier application.
#
# WHAT IS A VPC?
#   A VPC is your own private, isolated section of the AWS cloud. Think of it
#   like your own private data centre inside AWS. Nothing can get in or out
#   unless you explicitly allow it. Every resource we create (servers, databases,
#   containers) will live inside this VPC.
#
# NETWORK LAYOUT:
#   10.0.0.0/16  = the whole VPC (65,536 IP addresses)
#   ├── 10.0.1.0/24   = Public Subnet A  (256 IPs, eu-west-2a) — internet-facing
#   ├── 10.0.2.0/24   = Public Subnet B  (256 IPs, eu-west-2b) — internet-facing
#   ├── 10.0.10.0/24  = Private Subnet A (256 IPs, eu-west-2a) — no direct internet
#   └── 10.0.20.0/24  = Private Subnet B (256 IPs, eu-west-2b) — no direct internet
#
# WHY 2 AVAILABILITY ZONES?
#   AWS regions have multiple data centres called "Availability Zones" (AZs).
#   By placing subnets in 2 AZs, if one data centre has issues, your app
#   keeps running in the other. This is called "high availability".
#
# PUBLIC vs PRIVATE SUBNETS:
#   - Public subnets: resources here get a public IP and can talk to the internet
#     directly. Good for load balancers, bastion hosts.
#   - Private subnets: resources here have NO public IP. They reach the internet
#     only through a NAT Gateway. Good for app servers, databases — anything you
#     don't want the public internet to reach directly.
# =============================================================================

# -----------------------------------------------------------------------------
# THE VPC ITSELF
# -----------------------------------------------------------------------------
# This is the "container" for all our networking. The CIDR block defines the
# range of private IP addresses available inside the VPC.
#   - 10.0.0.0/16 gives us 65,536 addresses (10.0.0.0 to 10.0.255.255)
#   - enable_dns_support: lets resources inside the VPC resolve domain names
#   - enable_dns_hostnames: gives EC2 instances human-readable DNS names
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr # Passed in from the calling module (default: 10.0.0.0/16)

  # DNS settings — both must be true for things like RDS endpoints to work
  enable_dns_support   = true # Allows DNS resolution inside the VPC
  enable_dns_hostnames = true # Gives instances public DNS hostnames

  # Tags help you identify resources in the AWS console and on your bill.
  # We tag everything consistently so we can find and filter resources later.
  tags = {
    Name        = "${var.project_name}-vpc"       # Human-readable name in AWS console
    Project     = var.project_name                 # Which project owns this resource
    Environment = var.environment                  # dev / staging / production
    ManagedBy   = "terraform"                      # So we know not to edit it by hand
  }
}

# -----------------------------------------------------------------------------
# PUBLIC SUBNETS
# -----------------------------------------------------------------------------
# We create 2 public subnets, one in each Availability Zone.
# "count" lets us create multiple resources from a single block.
# count = length(var.public_subnet_cidrs) means "create one subnet per CIDR
# in the list", so if we pass ["10.0.1.0/24", "10.0.2.0/24"], we get 2 subnets.
#
# map_public_ip_on_launch = true is what makes these "public" — any instance
# launched here automatically gets a public IP address.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs) # Create one subnet per CIDR provided

  vpc_id     = aws_vpc.main.id                    # Attach to our VPC
  cidr_block = var.public_subnet_cidrs[count.index] # e.g., 10.0.1.0/24 for first, 10.0.2.0/24 for second
  availability_zone = var.availability_zones[count.index] # Spread across AZs for high availability

  # THIS is the key setting that makes a subnet "public". Instances launched
  # here will automatically receive a public IPv4 address.
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}" # e.g., "multi-tier-app-public-subnet-1"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "public"     # Extra tag so we can easily filter public vs private
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# PRIVATE SUBNETS
# -----------------------------------------------------------------------------
# Same approach as public subnets, but WITHOUT map_public_ip_on_launch.
# Resources in these subnets will NOT get a public IP. They can only reach
# the internet through the NAT Gateway (defined below).
# This is where we'll put our backend containers and database.
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs) # Create one subnet per CIDR provided

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index] # e.g., 10.0.10.0/24, 10.0.20.0/24
  availability_zone = var.availability_zones[count.index]

  # Note: we do NOT set map_public_ip_on_launch here — it defaults to false.
  # That's what keeps these subnets private.

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "private"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# INTERNET GATEWAY (IGW)
# -----------------------------------------------------------------------------
# The Internet Gateway is the "door" between your VPC and the public internet.
# Without it, nothing in your VPC can reach the internet (and vice versa).
# There is no charge for the IGW itself — you only pay for data transfer.
# A VPC can have exactly ONE Internet Gateway.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # Attach to our VPC

  tags = {
    Name        = "${var.project_name}-igw"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# ELASTIC IP FOR NAT GATEWAY
# -----------------------------------------------------------------------------
# A NAT Gateway needs a static public IP address (called an Elastic IP in AWS).
# This is a fixed IP that won't change even if the NAT Gateway is recreated.
#
# COST NOTE: Elastic IPs are FREE while attached to a running resource.
# They cost ~$3.60/month if allocated but NOT attached. Always clean up!
resource "aws_eip" "nat" {
  domain = "vpc" # Tells AWS this EIP is for use inside a VPC

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # We need the IGW to exist before creating VPC EIPs.
  # "depends_on" explicitly tells Terraform about this ordering requirement.
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT GATEWAY
# -----------------------------------------------------------------------------
# The NAT (Network Address Translation) Gateway lets resources in PRIVATE
# subnets reach the internet (e.g., to download software updates, pull Docker
# images) WITHOUT being directly reachable from the internet.
#
# HOW IT WORKS:
#   Private instance → sends traffic to NAT GW → NAT GW forwards to internet
#   Internet response → comes back to NAT GW → NAT GW forwards to private instance
#   The outside world only sees the NAT Gateway's IP, never the private instance.
#
# COST NOTE: NAT Gateways cost ~$32/month + data transfer charges.
#   We use a SINGLE NAT GW (in one AZ) to save money during development.
#   In production, you'd want one per AZ for high availability.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id              # The static IP we just created
  subnet_id     = aws_subnet.public[0].id     # Must be in a PUBLIC subnet (first one: eu-west-2a)

  tags = {
    Name        = "${var.project_name}-nat-gw"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # The NAT Gateway needs the Internet Gateway to exist first,
  # because it routes traffic through the IGW to reach the internet.
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE
# -----------------------------------------------------------------------------
# A route table is like a set of directions telling network traffic where to go.
# This route table says: "For any traffic going to the internet (0.0.0.0/0),
# send it through the Internet Gateway."
#
# Every subnet must be associated with a route table. Subnets associated with
# this route table become "public" because they can route directly to the internet.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # This route sends ALL internet-bound traffic (0.0.0.0/0 means "any IP address")
  # to the Internet Gateway. This is what makes the subnets truly public.
  route {
    cidr_block = "0.0.0.0/0"               # Destination: anywhere on the internet
    gateway_id = aws_internet_gateway.main.id # Next hop: the Internet Gateway
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE
# -----------------------------------------------------------------------------
# This route table is for private subnets. Instead of routing to the IGW,
# it routes internet-bound traffic through the NAT Gateway.
# This means private resources CAN reach the internet (outbound), but the
# internet CANNOT reach them (inbound). Perfect for backend services.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Internet-bound traffic goes through the NAT Gateway instead of the IGW.
  # The NAT Gateway translates the private IP to its own public IP.
  route {
    cidr_block     = "0.0.0.0/0"             # Destination: anywhere on the internet
    nat_gateway_id = aws_nat_gateway.main.id  # Next hop: the NAT Gateway
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# ROUTE TABLE ASSOCIATIONS — PUBLIC SUBNETS
# -----------------------------------------------------------------------------
# A route table does nothing until you associate it with a subnet.
# Here we link each public subnet to the public route table.
# This is what actually makes them "public" — they can now route to the IGW.
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs) # One association per public subnet

  subnet_id      = aws_subnet.public[count.index].id # The subnet to associate
  route_table_id = aws_route_table.public.id          # The route table to use
}

# -----------------------------------------------------------------------------
# ROUTE TABLE ASSOCIATIONS — PRIVATE SUBNETS
# -----------------------------------------------------------------------------
# Same idea: link each private subnet to the private route table.
# Traffic from these subnets will go through the NAT Gateway.
resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs) # One association per private subnet

  subnet_id      = aws_subnet.private[count.index].id # The subnet to associate
  route_table_id = aws_route_table.private.id           # The route table to use
}
