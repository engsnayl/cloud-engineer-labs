# Hints — Cloud Lab 015: Conditional Logic

## Hint 1 — Read each conditional carefully
`condition ? true_value : false_value` — check if the logic matches the intent. Bastion should be in staging only, monitoring should be enabled when the variable is true.

## Hint 2 — for_each needs a set or map
`for_each = var.subnet_cidrs` fails because it's a list. Use `for_each = toset(var.subnet_cidrs)`.

## Hint 3 — Dynamic block iterator
In a dynamic block, `ingress.value` gives you the current item. `ingress.key` gives the index (0, 1, 2) which is wrong for port numbers.
