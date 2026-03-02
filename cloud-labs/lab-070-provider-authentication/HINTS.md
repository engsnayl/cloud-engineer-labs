# Hints — Cloud Lab 011: Provider Authentication

## Hint 1 — Invalid region
"eu-west-99" isn't a real AWS region. Valid EU regions include eu-west-1, eu-west-2, eu-west-3.

## Hint 2 — Duplicate provider blocks
You can't have two AWS providers without aliases. The second one needs `alias = "backup_region"`.

## Hint 3 — Provider reference
The s3 backup bucket references `aws.backup_region` which needs to match the alias on the second provider block.
