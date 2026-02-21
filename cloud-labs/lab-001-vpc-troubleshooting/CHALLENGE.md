Title: VPC Networking — EC2 Instance Can't Reach the Internet
Difficulty: ⭐⭐⭐ (Intermediate-Advanced)
Time: 20-30 minutes
Category: AWS Networking / VPC
Skills: VPC, Subnets, Route Tables, Internet Gateway, Security Groups, NACLs

## Scenario

The platform team has provisioned a new VPC for a microservices deployment, but something isn't right:

> **INCIDENT-5102**: New EC2 instance in the application subnet cannot reach the internet. The instance needs outbound access to pull container images from ECR and communicate with external payment APIs. Security team confirms the instance should have outbound internet access via NAT, but direct inbound from the internet should be blocked.

The Terraform has been applied but the networking is misconfigured in several ways. Your job is to identify and fix the issues.

## Objectives

1. Run `terraform apply` to provision the broken VPC environment
2. SSH into the EC2 instance (or use SSM Session Manager)
3. Diagnose why the instance has no outbound internet connectivity
4. Fix the Terraform configuration (NOT the console — fix the code)
5. Re-apply and validate

## What's Been Provisioned (Broken)

- 1 VPC (10.0.0.0/16)
- 1 public subnet (10.0.1.0/24)
- 1 private subnet (10.0.2.0/24)
- 1 Internet Gateway
- 1 NAT Gateway
- Route tables for each subnet
- 1 EC2 instance in the private subnet
- Security groups and NACLs

## What You're Practising

VPC networking is the #1 topic that trips up cloud engineers. Understanding route tables, the relationship between IGW/NAT/subnets, and how security groups and NACLs interact is fundamental to every cloud role. This is also a Terraform debugging exercise — you fix infrastructure as code, not by clicking.
