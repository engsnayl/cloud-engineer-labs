# Hints — Cost Tagging & Budgets

## Hint 1
Terraform's `default_tags` in the provider block automatically applies tags to ALL resources. This is more reliable than tagging each resource individually.

## Hint 2
The `common_tags` local is defined but never used. Apply it to resources using `tags = local.common_tags`.

## Hint 3
AWS Budgets support notification blocks with threshold percentages and SNS topic ARNs. You need at least an 80% and 100% threshold.

## Hint 4
A billing alarm threshold of $0 means it fires constantly. Set it to your actual monthly budget ceiling.

## Hint 5
Cost allocation tags must be activated in the AWS Billing console before they appear in Cost Explorer. Terraform can create the tags but activation is manual.
