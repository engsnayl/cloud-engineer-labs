# Solution Walkthrough — Terraform Conditional Logic Bugs

## The Problem

Terraform's conditional logic is creating the wrong resources in the wrong environments. The configuration uses `count`, `for_each`, and dynamic blocks, but the logic has **four bugs**:

1. **Inverted bastion condition** — the bastion host is created in production (`count = var.environment == "production" ? 1 : 0`) but should only exist in staging. The condition is backwards.
2. **`for_each` on a list** — `for_each = var.subnet_cidrs` fails because `for_each` requires a set or map, not a list. Lists need `toset()` conversion.
3. **Dynamic block uses `ingress.key` instead of `ingress.value`** — `ingress.key` returns the index (0, 1, 2), not the port numbers (80, 443, 8080). The security group gets rules for ports 0, 1, 2 instead of the intended ports.
4. **Inverted monitoring condition** — `count = var.enable_monitoring ? 0 : 1` creates the alarm when monitoring is disabled and skips it when enabled. The ternary values are swapped.

## Thought Process

When Terraform conditional logic produces wrong results, an experienced engineer:

1. **Read each conditional carefully** — `condition ? true_value : false_value`. Verify the condition matches the intent: "if X, then create" means `count = X ? 1 : 0`.
2. **Check `for_each` types** — `for_each` accepts `set` or `map`, never `list`. Wrap lists with `toset()`.
3. **Check dynamic block iterators** — `iterator.value` gives the element, `iterator.key` gives the index. For lists of ports, you want `.value`.
4. **Test with `terraform plan`** — the plan shows exactly what would be created. Check that the right resources appear for the right conditions.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Invert the bastion condition

```hcl
# BROKEN — creates bastion in production
resource "aws_instance" "bastion" {
  count         = var.environment == "production" ? 1 : 0
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  tags = { Name = "bastion-host" }
}

# FIXED — creates bastion in staging only
resource "aws_instance" "bastion" {
  count         = var.environment == "staging" ? 1 : 0
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  tags = { Name = "bastion-host" }
}
```

**Why this matters:** Bastion hosts (jump boxes) are used for SSH access to private instances. They're appropriate for staging/development environments where engineers need direct access, but in production, access should be through more secure channels (SSM Session Manager, VPN). The condition `== "production" ? 1 : 0` creates the bastion in production — the opposite of the intent.

### Step 2: Fix Bug 2 — Wrap list with toset()

```hcl
# BROKEN — for_each on a list
resource "aws_subnet" "app" {
  for_each   = var.subnet_cidrs          # List — won't work!
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value
}

# FIXED — convert to set
resource "aws_subnet" "app" {
  for_each   = toset(var.subnet_cidrs)   # Set — works!
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value
}
```

**Why this matters:** `for_each` requires a `set` or `map` because Terraform uses the keys for resource addressing. With a list, items are identified by index (0, 1, 2), which breaks if you reorder items. With a set, items are identified by their value ("10.0.1.0/24"), which is stable. `toset()` converts a list to a set.

### Step 3: Fix Bug 3 — Use ingress.value for ports

```hcl
# BROKEN — uses ingress.key (index: 0, 1, 2)
dynamic "ingress" {
  for_each = [80, 443, 8080]
  content {
    from_port   = ingress.key      # Returns 0, 1, 2!
    to_port     = ingress.key
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# FIXED — uses ingress.value (ports: 80, 443, 8080)
dynamic "ingress" {
  for_each = [80, 443, 8080]
  content {
    from_port   = ingress.value    # Returns 80, 443, 8080
    to_port     = ingress.value
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Why this matters:** In a `dynamic` block iterating over a list:
- **`ingress.key`** — the index position (0, 1, 2). This creates rules for ports 0, 1, and 2 — completely wrong.
- **`ingress.value`** — the actual list element (80, 443, 8080). This creates rules for HTTP, HTTPS, and the custom port — correct.

### Step 4: Fix Bug 4 — Invert the monitoring condition

```hcl
# BROKEN — creates alarm when monitoring is disabled
resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.enable_monitoring ? 0 : 1    # Inverted!
}

# FIXED — creates alarm when monitoring is enabled
resource "aws_cloudwatch_metric_alarm" "cpu" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
}
```

**Why this matters:** The ternary `condition ? true_value : false_value` evaluates to `true_value` when the condition is true. `var.enable_monitoring ? 0 : 1` means "if monitoring is enabled, count is 0 (don't create)" — the exact opposite of the intent. Swapping 0 and 1 fixes it.

### Step 5: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **`count` vs `for_each` for conditionals:** `count = condition ? 1 : 0` is the standard pattern for optional resources. `for_each` is better when you need to create multiple resources with different configurations.
- **Feature flags:** In production, variables like `enable_monitoring` act as feature flags. They allow enabling or disabling capabilities per environment without changing code.
- **Module-level conditionals:** In complex configurations, entire modules can be conditionally included: `module "monitoring" { count = var.enable_monitoring ? 1 : 0 }`.
- **Type constraints:** Use `type = bool` for feature flags and `type = string` with `validation` for environment names. This catches errors at plan time instead of runtime.
- **Testing conditionals:** Tools like `terraform-compliance`, `checkov`, and `tflint` can verify that conditionals produce the expected resources for each environment.

## Key Concepts Learned

- **`count = condition ? 1 : 0` is the conditional resource pattern** — creates the resource when true, skips it when false. Getting 1 and 0 backwards inverts the logic.
- **`for_each` requires a set or map, not a list** — use `toset()` to convert lists. This ensures stable resource addressing.
- **Dynamic block `.value` vs `.key`** — `.value` gives the element, `.key` gives the index. For port lists, you almost always want `.value`.
- **Read ternary expressions carefully** — `A ? B : C` means "if A then B else C." It's easy to swap B and C, creating inverted behavior.
- **`terraform plan` reveals conditional logic bugs** — the plan shows exactly which resources would be created. If a bastion appears in a production plan, the logic is wrong.

## Common Mistakes

- **Swapping true and false values in ternaries** — `condition ? 1 : 0` vs `condition ? 0 : 1` — one creates the resource when true, the other when false. This is the most common conditional bug.
- **Using `for_each` on a list** — Terraform errors with "The given 'for_each' argument value is unsuitable." Always use `toset()` for lists.
- **Confusing `.key` and `.value` in dynamic blocks** — for a list `[80, 443]`, `.key` is `0, 1` and `.value` is `80, 443`. Wrong reference = wrong port numbers.
- **Not handling the "default" case** — if `var.environment` could be "dev", "staging", or "production," make sure all conditionals handle all possible values.
- **Nested ternaries for readability** — `a ? (b ? c : d) : e` is hard to read. Use locals to break complex conditionals into named, readable pieces.
