# Solution Walkthrough — CloudFormation Stack Failed

## The Problem

A CloudFormation template has multiple errors preventing deployment. There are **five bugs**:

1. **Wrong intrinsic function for string interpolation** — `!Ref "${EnvironmentName}-vpc"` is invalid. `!Ref` takes a single logical name, not a string. Use `!Sub "${EnvironmentName}-vpc"` for interpolation.
2. **GetAtt instead of Ref for VPC ID** — `!GetAtt VPC.VpcId` is not a valid attribute for AWS::EC2::VPC. `!Ref VPC` returns the VPC ID directly.
3. **FromPort/ToPort with protocol -1** — when IpProtocol is "-1" (all traffic), FromPort and ToPort must not be specified (or some tools reject them).
4. **Missing ImageId** — EC2 instances require an AMI ID. Use an SSM parameter for the latest Amazon Linux 2023.
5. **Wrong GetAtt attribute name** — `WebInstance.IpAddress` is not valid. The correct attribute is `WebInstance.PublicIp`.

## Step-by-Step Solution

### Step 1: Fix the VPC name tag
```yaml
Value: !Sub "${EnvironmentName}-vpc"  # Was: !Ref "${EnvironmentName}-vpc"
```

### Step 2: Fix the subnet VPC reference
```yaml
VpcId: !Ref VPC  # Was: !GetAtt VPC.VpcId
```

### Step 3: Fix the egress rule
```yaml
SecurityGroupEgress:
  - IpProtocol: "-1"
    CidrIp: 0.0.0.0/0
    # Removed FromPort and ToPort
```

### Step 4: Add AMI parameter and reference
Add a parameter:
```yaml
Parameters:
  LatestAmiId:
    Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
    Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```
Reference it:
```yaml
ImageId: !Ref LatestAmiId
```

### Step 5: Fix the output attribute
```yaml
Value: !GetAtt WebInstance.PublicIp  # Was: WebInstance.IpAddress
```

## Key Concepts Learned

- **!Ref vs !Sub** — `!Ref` returns a resource ID or parameter value (no interpolation). `!Sub` performs string substitution with `${Variable}` syntax.
- **!Ref vs !GetAtt** — `!Ref` returns the primary identifier (e.g., VPC ID, instance ID). `!GetAtt` returns specific attributes (e.g., PublicIp, Arn). Know which to use for each resource type.
- **SSM Parameter for AMIs** — hardcoding AMI IDs makes templates region-specific and outdated. Use SSM parameters to dynamically resolve the latest AMI.
- **Security group protocol rules** — protocol "-1" means all traffic. Don't specify ports with it.
- **CloudFormation attribute names** — each resource type has specific attributes available via GetAtt. Check the docs for the exact names.

## CloudFormation vs Terraform

If you're coming from Terraform, key differences:
- **State management** — CloudFormation manages state automatically (no remote backend needed). Terraform requires explicit state configuration.
- **Rollback** — CloudFormation automatically rolls back failed stacks. Terraform leaves partial state that you must clean up.
- **Syntax** — CloudFormation uses YAML/JSON with intrinsic functions. Terraform uses HCL with interpolation syntax.
- **Provider support** — Terraform supports multi-cloud. CloudFormation is AWS-only.
- **Drift detection** — both support it, but differently. CloudFormation has built-in drift detection. Terraform uses `terraform plan` to show drift.
