provider "aws" {
  region = "eu-west-2"
}

variable "environment" {
  default = "production"
}

# =============================================================================
# NETWORKING
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2a"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# PRODUCTION WEB SERVERS
# =============================================================================

resource "aws_instance" "prod_web" {
  count                  = 3
  ami                    = "ami-0c76bd4bd302b30ec"
  instance_type          = "m5.2xlarge"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.web.id]

  root_block_device {
    volume_size = 200
    volume_type = "gp3"
  }
}

resource "aws_security_group" "web" {
  name_prefix = "web-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =============================================================================
# DEVELOPMENT ENVIRONMENT
# =============================================================================

resource "aws_instance" "dev_web" {
  count                  = 3
  ami                    = "ami-0c76bd4bd302b30ec"
  instance_type          = "m5.xlarge"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.dev.id]

  root_block_device {
    volume_size = 200
    volume_type = "gp3"
  }
}

resource "aws_instance" "dev_worker" {
  count                  = 2
  ami                    = "ami-0c76bd4bd302b30ec"
  instance_type          = "m5.xlarge"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.dev.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }
}

resource "aws_security_group" "dev" {
  name_prefix = "dev-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =============================================================================
# DATABASE
# =============================================================================

resource "aws_db_instance" "main" {
  identifier             = "app-database"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.r5.2xlarge"
  allocated_storage      = 500
  max_allocated_storage  = 1000
  db_name                = "appdb"
  username               = "admin"
  password               = "supersecretpassword123"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  multi_az               = false
  storage_type           = "io1"
  iops                   = 3000
}

resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = [aws_subnet.private.id, aws_subnet.private_b.id]
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-2b"
}

resource "aws_security_group" "db" {
  name_prefix = "db-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =============================================================================
# STORAGE
# =============================================================================

resource "aws_s3_bucket" "app_data" {
  bucket = "company-app-data-prod-20240101"
}

resource "aws_s3_bucket" "logs" {
  bucket = "company-application-logs-20240101"
}

resource "aws_s3_bucket" "backups" {
  bucket = "company-db-backups-20240101"
}

resource "aws_s3_bucket" "dev_artifacts" {
  bucket = "company-dev-build-artifacts-20240101"
}

resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "dev_artifacts" {
  bucket = aws_s3_bucket.dev_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}
