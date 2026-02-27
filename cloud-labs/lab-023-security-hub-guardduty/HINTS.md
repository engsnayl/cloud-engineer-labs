# Hints — Security Hub & GuardDuty

## Hint 1
Check whether GuardDuty is actually enabled. A detector that exists but isn't enabled won't generate findings.

## Hint 2
GuardDuty has multiple data sources — S3 logs, Kubernetes audit logs, etc. Are all the ones you need turned on?

## Hint 3
Security Hub needs explicit product integrations to receive findings from other services. Check the AWS docs for `aws_securityhub_product_subscription`.

## Hint 4
The EventBridge rule filters on severity labels. What severity levels should you actually be alerting on for a security pipeline?

## Hint 5
EventBridge needs permission to publish to SNS. Check which AWS service principal EventBridge uses.
