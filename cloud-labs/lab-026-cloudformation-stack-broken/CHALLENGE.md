Title: CloudFormation Stack Failed — Template Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / CloudFormation
Skills: CloudFormation templates, YAML, intrinsic functions, resource references, parameters

## Scenario

A colleague wrote a CloudFormation template to deploy a simple web application (VPC, EC2 instance, security group). The stack creation fails with multiple errors. You need to fix the template so it deploys successfully.

> **INCIDENT-CFN-001**: CloudFormation stack "web-app-stack" stuck in CREATE_FAILED. Team needs this environment for testing by end of day. Template has errors that need fixing.

## Objectives

1. Fix the parameter reference syntax errors
2. Fix the intrinsic function usage (Ref, Fn::GetAtt, Fn::Sub)
3. Fix the resource dependency issues
4. Fix the security group rule configuration
5. Template must pass `aws cloudformation validate-template`

## How to Use This Lab

1. Review `template.yaml` — find and fix the bugs
2. Validate with `aws cloudformation validate-template --template-body file://template.yaml`
3. (Optional) Deploy with `aws cloudformation create-stack --stack-name lab-026 --template-body file://template.yaml`

**Requires:** AWS CLI installed. AWS credentials for deploy (optional — you can learn from validate alone).

## Validation

Run `./validate.sh` to check template validity.
