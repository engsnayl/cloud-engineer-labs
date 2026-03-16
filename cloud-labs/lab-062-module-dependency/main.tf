provider "aws" {
  region = "eu-west-2"
}

module "vpc" {
  source = "./modules/vpc"
}

module "ec2" {
  source = "./modules/ec2"

  vpc_id    = module.networking.vpc_id
  subnet_id = module.vpc.private_subnet
}
