# Hints — Cloud Lab 020: CloudWatch Alarms

## Hint 1 — Comparison operator
"LessThanThreshold" with threshold 80 means it alarms when CPU is BELOW 80% — the opposite of what you want.

## Hint 2 — Three things missing from the CPU alarm
1. Comparison should be GreaterThanThreshold. 2. alarm_actions needs the SNS topic ARN. 3. dimensions needs the InstanceId.

## Hint 3 — Status check period
3600 seconds means the alarm evaluates only once per hour. Use 60 seconds for status checks.
