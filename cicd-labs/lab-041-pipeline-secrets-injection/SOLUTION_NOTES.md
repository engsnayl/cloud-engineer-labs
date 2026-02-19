# Solution Notes

## Never bake secrets into Docker images
- Don't use ARG/ENV for credentials
- Use runtime injection (ECS task definition, K8s secrets, etc.)
- AWS credentials should come from IAM roles, not env vars

## Secret naming convention
- GitHub secrets should be consistently named
- AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are standard names

## Runtime secrets pattern
- Database URLs: inject via environment variables at deploy time
- AWS credentials: use IAM roles (ECS task role, EC2 instance profile)
- Application secrets: use AWS Secrets Manager or Parameter Store
