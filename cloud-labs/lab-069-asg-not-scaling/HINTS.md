# Hints — Cloud Lab 010: ASG Not Scaling

## Hint 1 — Max size
If max_size = min_size = 1, the ASG physically cannot add instances. Increase max_size.

## Hint 2 — Scaling adjustment type
`ExactCapacity` with value 1 means "set to exactly 1 instance" — not helpful when you're already at 1. Change to `ChangeInCapacity` so it adds 1 instance.

## Hint 3 — Recommended fix
Set max_size to 4 or higher, and change adjustment_type to "ChangeInCapacity" so scaling_adjustment = 1 means "add 1 more instance".
