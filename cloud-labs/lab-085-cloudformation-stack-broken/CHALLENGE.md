Title: CloudFormation Stack Failed — Template Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 20-30 minutes
Category: AWS / CloudFormation
Skills: CloudFormation templates, YAML, intrinsic functions, resource references, parameters, SSM parameter lookups

## What You'll Practise

- Reading CloudFormation event logs to trace failure causes
- Distinguishing template-syntax errors from property-level and service-level errors
- Using `!Ref`, `!Sub`, and `!GetAtt` intrinsic functions correctly
- Resolving AMI IDs dynamically via SSM parameters
- Handling CloudFormation's ROLLBACK_COMPLETE lifecycle state
- Understanding the deploy-verify-destroy workflow for CloudFormation stacks

## Scenario

A colleague wrote a CloudFormation template to deploy a simple web application — a VPC, a public subnet, a security group, and an EC2 instance running Apache. When they try to deploy the stack, it fails. They've handed you the ticket.

> **INCIDENT-CFN-001**: CloudFormation stack "lab-085" stuck in CREATE_FAILED. Team needs this environment for testing by end of day. Template has errors that need fixing.

There are multiple bugs in the template. Each one surfaces at a different point in the CloudFormation lifecycle — some caught by template validation, some only caught when AWS tries to create the resource, some only caught when CloudFormation resolves the Outputs section. You need to find and fix them all, then prove the deployment works by curling the EC2 instance.

## Objectives

1. Fix the intrinsic function bugs in the template
2. Add a missing required property using the industry-standard SSM-parameter AMI lookup pattern
3. Fix the Outputs section to expose the correct EC2 attribute
4. Deploy the stack successfully and verify the web server responds
5. Destroy the stack cleanly when done

## How to Use This Lab

1. Read `template.yaml` and understand the intended architecture
2. Run `aws cloudformation validate-template --template-body file://template.yaml --region eu-west-2` to catch the first bug
3. Fix, redeploy, watch the event log, fix the next bug — repeat until the stack reaches CREATE_COMPLETE
4. Curl the public IP from the stack Outputs to verify the web server is live
5. Destroy with `aws cloudformation delete-stack` and verify teardown completed
6. Run `./validate.sh` to confirm your fixes

**Requires:** AWS CLI installed, AWS credentials configured, permission to create VPCs and EC2 instances in eu-west-2 (or your default region — adjust commands accordingly).

**Cost:** This lab deploys a real t3.micro EC2 instance. If you destroy promptly, cost is negligible (pennies). If you leave it running, ~£6–7/month.

## Validation

Run `./validate.sh` to check your template has the right fixes. Note that the validate script does **static analysis** — it confirms the bugs are fixed but doesn't deploy. A full deploy-verify-destroy round trip is part of the lab, not the validator.
