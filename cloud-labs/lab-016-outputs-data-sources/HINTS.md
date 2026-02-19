# Hints — Cloud Lab 016: Outputs and Data Sources

## Hint 1 — Use a data source for the AMI
Uncomment the `data "aws_ami"` block and reference it: `ami = data.aws_ami.ubuntu.id`

## Hint 2 — Add the missing outputs
```hcl
output "vpc_id" { value = aws_vpc.main.id }
output "subnet_id" { value = aws_subnet.app.id }
output "instance_id" { value = aws_instance.app.id }
```

## Hint 3 — Fix the IP output
If the instance doesn't have a public IP, the output should say private_ip in both the value AND the description.
