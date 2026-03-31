# Discovery Worksheet — Lab 091

Use this worksheet to document every resource you find. In real life, this is the deliverable your client is paying for — the complete picture of what exists before you start writing code.

---

## Discovery Commands Used

| Command | What It Found |
|---------|--------------|
| `aws ec2 describe-vpcs --filters ...` | |
| | |
| | |
| | |
| | |
| | |

---

## Resources Discovered

### Networking

| Resource Type | Resource ID | Name Tag | Key Details |
|--------------|------------|----------|-------------|
| VPC | | | CIDR: |
| Subnet | | | AZ: , CIDR: |
| Subnet | | | AZ: , CIDR: |
| Internet Gateway | | | Attached to: |
| Route Table | | | Routes: |

### Compute & Security

| Resource Type | Resource ID | Name Tag | Key Details |
|--------------|------------|----------|-------------|
| Security Group | | | Ports open: |

### Storage

| Resource Type | Resource ID / Name | Key Details |
|--------------|-------------------|-------------|
| S3 Bucket | | Versioning: , Region: |

### IAM

| Resource Type | Resource Name | Key Details |
|--------------|--------------|-------------|
| IAM Role | | Trust: , Policies attached: |

---

## Dependency Map

_Draw the dependency chain — which resources depend on which? This determines your import order._

```
VPC
├── Subnet (public)
│   └── ...
├── Subnet (private)
├── Internet Gateway
├── Route Table
│   └── ...
└── Security Group

S3 Bucket (independent)
IAM Role (independent)
```

---

## Import Order

_List the order you'll import resources (dependencies first):_

1. 
2. 
3. 
4. 
5. 
6. 
7. 
8. 

---

## Notes / Surprises

_Anything unexpected you found during discovery:_
