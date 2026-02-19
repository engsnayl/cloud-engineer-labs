# Module Dependency Lab
provider "aws" {
  region = "eu-west-2"
}

module "vpc" {
  source = "./modules/vpc"
}

module "ec2" {
  source = "./modules/ec2"

  # BUG 1: Wrong output reference
  vpc_id    = module.networking.vpc_id
  # BUG 2: Wrong output name
  subnet_id = module.vpc.private_subnet
}
