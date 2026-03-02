# Hints — Cloud Lab 004: S3 Bucket Policy

## Hint 1 — Explicit Deny wins
An explicit Deny in any policy overrides all Allows. Check the bucket policy for any Deny statements.

## Hint 2 — Three issues
1. The first bucket policy statement has Effect: "Deny" with Principal: "*" — this blocks everyone. 2. ListBucket needs the bucket ARN (without /*), not the object ARN. 3. The IAM policy Resource needs both the bucket ARN and the objects ARN (bucket/* ).

## Hint 3 — S3 resource patterns
For object operations (Get/Put): `arn:aws:s3:::bucket/*`
For bucket operations (List): `arn:aws:s3:::bucket`
IAM policies often need both: `["arn:aws:s3:::bucket", "arn:aws:s3:::bucket/*"]`
