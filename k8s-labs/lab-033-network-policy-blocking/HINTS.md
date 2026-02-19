# Hints — Lab 033: Network Policy Blocking

## Hint 1 — Check the policy
`kubectl describe networkpolicy db-restrict -n production` shows what traffic is allowed.

## Hint 2 — Compare with pod labels
The policy only allows pods with `role: admin` but the API pods have `role: api`. You need to add `role: api` to the allowed selectors.

## Hint 3 — Add the API selector
Add another `podSelector` entry for `role: api` in the ingress rules. Each `- podSelector` is an OR condition.
