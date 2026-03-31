# Hints — Lab 090: AWS Cost Optimisation

## Hint 1 — Start with the biggest line items
EC2 instances and RDS are typically the largest cost drivers. Look at the instance types — are they appropriate for the workload described? A small company's web servers and dev environment don't need the same hardware as Netflix.

## Hint 2 — Dev doesn't need to run 24/7
If developers work 8am-6pm Monday to Friday, that's only 50 hours out of 168 in a week. Every hour those dev instances run overnight and at weekends is pure waste.

## Hint 3 — Storage without lifecycle policies grows forever
Logs and build artifacts accumulate endlessly unless you tell S3 to clean them up. Think about what a reasonable retention period would be for each bucket type.

## Hint 4 — Provisioned IOPS vs General Purpose
io1 storage with provisioned IOPS is expensive and designed for high-performance database workloads. Does a small company's MySQL database actually need 3000 IOPS?

## Hint 5 — Check the security groups
This isn't a cost issue, but it's something an auditor would flag immediately. Look at what ports are open and to whom.

## Hint 6 — Tags aren't just labels
Without cost allocation tags, nobody can answer "which team is spending what?" That's exactly why finance can't explain the bill increase.
