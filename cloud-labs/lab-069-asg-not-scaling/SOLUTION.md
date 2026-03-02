# Solution Walkthrough — ASG Not Scaling

## The Problem

An Auto Scaling Group (ASG) should scale up when CPU exceeds 70%, but it stays stuck at 1 instance despite high CPU. The CloudWatch alarm is firing, the scaling policy exists, but the ASG won't add instances. There are **two key bugs** (plus a best-practice issue):

1. **`max_size` equals `min_size`** — both are set to 1. The ASG physically cannot add instances because its maximum capacity is 1. Even if the scaling policy triggers, the ASG can't exceed its max_size.
2. **Wrong scaling adjustment type** — `adjustment_type = "ExactCapacity"` with `scaling_adjustment = 1` means "set the desired count to exactly 1." Since it's already at 1, nothing happens. It should be `"ChangeInCapacity"` so that `scaling_adjustment = 1` means "add 1 more instance."
3. **Health check type** — using `"EC2"` health checks only monitors the instance's system status. If the ASG is behind a load balancer, `"ELB"` health checks would also check whether the application is responding.

## Thought Process

When an ASG isn't scaling despite CloudWatch alarms, an experienced cloud engineer checks:

1. **ASG capacity limits** — if `max_size == desired_capacity`, the ASG can't scale up. Check `min_size`, `max_size`, and `desired_capacity`.
2. **Scaling policy configuration** — what does the policy actually do? `ExactCapacity` sets a fixed count, `ChangeInCapacity` adds/removes, `PercentChangeInCapacity` scales by percentage.
3. **Alarm → Policy link** — is the CloudWatch alarm's `alarm_actions` pointing to the correct scaling policy ARN?
4. **Cooldown period** — after a scaling action, the ASG ignores further triggers for the cooldown period. If cooldown is very long, it may appear stuck.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Increase max_size

```hcl
# BROKEN
resource "aws_autoscaling_group" "app" {
  min_size         = 1
  max_size         = 1    # Can't scale beyond 1!
  desired_capacity = 1
}

# FIXED
resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  min_size            = 1
  max_size            = 4     # Now can scale up to 4 instances
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.app.id]
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
```

**Why this matters:** `max_size` is a hard ceiling. The ASG will never exceed this number, regardless of what scaling policies say. Setting `max_size = 1` means the ASG is locked at 1 instance forever. Increasing it to 4 (or higher) gives the scaling policy room to add instances.

### Step 2: Fix Bug 2 — Change adjustment type to ChangeInCapacity

```hcl
# BROKEN
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ExactCapacity"    # Sets count to exactly 1
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

# FIXED
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"  # Adds 1 instance
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}
```

**Why this matters:** The three adjustment types work differently:
- **`ExactCapacity`** — sets desired count to the exact value. `scaling_adjustment = 1` means "set to 1 instance" (useless for scale-up when already at 1).
- **`ChangeInCapacity`** — adds or removes the value. `scaling_adjustment = 1` means "add 1 more instance" (correct for scale-up).
- **`PercentChangeInCapacity`** — scales by percentage. `scaling_adjustment = 50` means "add 50% more instances."

For simple scale-up, `ChangeInCapacity` is the most common choice.

### Step 3: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid. The plan should show the ASG with `max_size = 4` and the scaling policy with `adjustment_type = "ChangeInCapacity"`.

## Docker Lab vs Real Life

- **Target tracking policies:** In production, target tracking scaling policies are preferred over simple step policies. For example: `target_tracking_configuration { predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" } target_value = 70 }` automatically manages scale-up and scale-down to maintain 70% CPU.
- **Scale-down policies:** This lab only has a scale-up policy. In production, you also need a scale-down policy (or use target tracking, which handles both directions).
- **Warm pools:** For applications with slow startup times, ASG warm pools keep pre-initialized instances ready to launch instantly when scaling up.
- **Instance refresh:** When updating the launch template, use instance refresh to gradually replace old instances with new ones without downtime.
- **Predictive scaling:** For workloads with predictable patterns (like daily traffic peaks), predictive scaling pre-warms capacity based on historical data.

## Key Concepts Learned

- **`max_size` is a hard ceiling** — the ASG cannot exceed this value. If `max_size == desired_capacity`, no scale-up is possible.
- **`ExactCapacity` vs `ChangeInCapacity`** — ExactCapacity sets an absolute count; ChangeInCapacity adds/removes from the current count. Using the wrong one makes scaling policies useless.
- **CloudWatch alarms trigger scaling policies** — the alarm's `alarm_actions` must reference the scaling policy ARN. The alarm evaluates the metric, and when it enters ALARM state, it triggers the policy.
- **Cooldown prevents rapid scaling** — after a scaling action, the ASG waits for the cooldown period before responding to more alarms. 300 seconds (5 minutes) is a common default.

## Common Mistakes

- **Setting max_size too low** — this is the most common ASG issue. If max equals desired, the ASG can't scale up. Always set max_size higher than your expected peak capacity.
- **Using ExactCapacity for scale-up** — ExactCapacity with value 1 means "set to 1" — not "add 1." This is the exact mistake in this lab.
- **Forgetting to create a scale-down policy** — without scale-down, instances added during traffic spikes never get removed. You keep paying for them even when load is low.
- **Not testing scaling in staging** — scaling policies should be tested under load before production. Use tools like `stress` or AWS Fault Injection Simulator.
- **Very long cooldown periods** — a 30-minute cooldown means the ASG can only add one instance every 30 minutes. For sudden traffic spikes, this is too slow.
