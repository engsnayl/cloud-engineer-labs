# Hints — CloudFormation Stack Failed

## Hint 1
`!Ref` returns the resource ID or parameter value. It doesn't do string interpolation. For that, use `!Sub`.

## Hint 2
For VPC resources, `!Ref VPC` returns the VPC ID directly. `!GetAtt VPC.VpcId` is redundant and may not be a valid attribute.

## Hint 3
When IpProtocol is "-1" (all traffic), you shouldn't specify FromPort and ToPort.

## Hint 4
Every EC2 instance needs an AMI. Consider using an SSM parameter to get the latest Amazon Linux 2 AMI dynamically.

## Hint 5
EC2 instance attributes in CloudFormation use specific names. The public IP attribute is `PublicIp`, not `IpAddress`.
