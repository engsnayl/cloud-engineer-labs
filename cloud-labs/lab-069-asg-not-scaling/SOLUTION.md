# Lab 069 — Solution Walkthrough: ASG Not Scaling

## TLDR (Plain English)

Someone set up an Auto Scaling Group that's supposed to add more servers when the CPU gets busy. It isn't working. The CPU is hot, the alarm is screaming, but no new servers appear.

Two things are wrong:

1. **The ASG is told it can never have more than 1 server.** So even when it's asked to add one, it can't — there's no room.
2. **The scaling rule is written wrong.** Instead of saying "add one more server," it says "make sure there is exactly 1 server." There already is 1. So it does nothing.

The fix is to raise the ceiling so the ASG is allowed to grow, and rewrite the scaling rule so it actually adds a server instead of re-stating the current count.

---

## The Ticket

> **INC-2047** — Production ASG `app-asg` not scaling under load. CPU sustained above 90% for the last hour. CloudWatch alarm `app-high-cpu` is in ALARM state. Still only 1 instance running. Please investigate and resolve.

That's all you've got. No one told you what's broken. You're the engineer on call. Let's walk in cold.

---

## Step 1 — Orient Yourself: What Are We Actually Looking At?

Before touching any code, confirm the facts in the ticket. Don't trust the reporter — trust the AWS API.

### 1a. Is the alarm really firing?

```bash
aws cloudwatch describe-alarms --alarm-names app-high-cpu
```

**Command breakdown:**

| Part | Meaning |
|---|---|
| `aws cloudwatch` | The CloudWatch service namespace in the AWS CLI |
| `describe-alarms` | Read-only API call — lists alarms and their current state |
| `--alarm-names app-high-cpu` | Filter to just the alarm we care about |

Look at `StateValue` in the output. If it says `ALARM`, the ticket is accurate — something *should* be happening and isn't.

### 1b. What does the ASG currently look like?

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names app-asg
```

**Command breakdown:**

| Part | Meaning |
|---|---|
| `aws autoscaling` | The Auto Scaling service namespace |
| `describe-auto-scaling-groups` | Read-only — returns full config of the ASG |
| `--auto-scaling-group-names app-asg` | Filter to our one ASG |

Three fields to eyeball immediately: `MinSize`, `MaxSize`, `DesiredCapacity`.

**This is the moment the first bug should jump out at you.** If you see `MinSize: 1, MaxSize: 1, DesiredCapacity: 1` — stop. That's your first clue. An ASG whose `MaxSize` equals its `DesiredCapacity` has nowhere to grow into. It is physically incapable of adding an instance, no matter how loud the alarm screams. The ceiling and the floor are the same board.

But don't fix it yet. Keep reading. There might be more.

### 1c. What does the scaling policy say to do?

```bash
aws autoscaling describe-policies --auto-scaling-group-name app-asg
```

Look at two fields in the output: `AdjustmentType` and `ScalingAdjustment`.

If you see `AdjustmentType: ExactCapacity` and `ScalingAdjustment: 1` — stop again. Read that out loud: *"When triggered, set the capacity to exactly 1."* The ASG is already at 1. The policy is telling it to become what it already is. Even if we fixed `MaxSize`, this policy would still be a no-op.

**That's bug two, found by reading, not guessing.**

---

## Step 2 — Find the Terraform That Defines This

You now know *what* is wrong in AWS. You need to find *where* it's declared in code so the fix survives the next `terraform apply`.

```bash
cd ~/cloud-engineer-labs/labs/terraform-aws/069-asg-not-scaling
ls
```

You should see `main.tf`, maybe `variables.tf`, `outputs.tf`. Open `main.tf`:

```bash
vi main.tf
```

Search for the ASG block — in `vi`, type `/aws_autoscaling_group` and press Enter. This jumps to the resource definition.

You're looking for the same two things you just saw in the AWS API:
- `min_size`, `max_size`, `desired_capacity` — are they all 1?
- In the `aws_autoscaling_policy` block, what is `adjustment_type`?

If the Terraform matches what AWS reported, good — you've confirmed the drift isn't someone having clicked in the console. The code is the source of truth, and the code is wrong.

---

## Step 3 — Reason About the First Fix (max_size)

**Question:** What should `max_size` be?

**Thought process:** `max_size` is the hard ceiling — the ASG will never exceed it. You need headroom above `desired_capacity` for scaling to have anywhere to go. How much headroom? That depends on expected peak load. For a lab, 4 is a sensible round number that proves scaling works without spinning up a fleet. In production you'd base this on load testing.

**Where do I change it?** In the `aws_autoscaling_group` block in `main.tf`. Not in the AWS console — console changes get overwritten on the next `terraform apply`.

```hcl
resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  min_size            = 1
  max_size            = 4    # was 1 — gives the policy room to scale
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.app.id]
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
```

---

## Step 4 — Reason About the Second Fix (adjustment_type)

**Question:** Which adjustment type do I actually want?

There are three options. Read them slowly:

| Type | What `scaling_adjustment = 1` means |
|---|---|
| `ExactCapacity` | "Set the desired count to exactly 1." |
| `ChangeInCapacity` | "Add 1 to the current count." |
| `PercentChangeInCapacity` | "Add 1% more instances (rounded)." |

The intent of a scale-up policy is *"when CPU is hot, give me one more box."* That's `ChangeInCapacity`. `ExactCapacity` is for rare cases where you want to force a specific number — for example, a scheduled action that resets the fleet to 3 every morning.

```hcl
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"   # was ExactCapacity
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}
```

---

## Step 5 — Validate Before Applying

```bash
terraform validate
terraform plan
```

**Command breakdown:**

| Part | Meaning |
|---|---|
| `terraform validate` | Checks syntax and internal references. No AWS calls. Fast. |
| `terraform plan` | Compares your code to real AWS state and shows what will change. Read-only against AWS. |

In the plan output, look for:
- `max_size: 1 -> 4` on the ASG
- `adjustment_type: "ExactCapacity" -> "ChangeInCapacity"` on the policy

If you see those two diffs and nothing else surprising, you're good.

```bash
terraform apply
```

---

## Step 6 — Prove It Worked

Don't just trust `apply` saying "Apply complete." Go back to the AWS API and check:

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names app-asg \
  --query 'AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]'
```

**New command part:**

| Part | Meaning |
|---|---|
| `--query '...'` | JMESPath filter — pulls only the fields you want instead of the full blob |
| `AutoScalingGroups[0]` | First (only) ASG in the result list |
| `[MinSize,MaxSize,DesiredCapacity]` | Return just these three fields as an array |

You should now see `[1, 4, 1]`. The ceiling has been lifted. Next time the alarm fires, the policy will add an instance and `DesiredCapacity` will climb.

---

## The Diagnostic Pathway (Memorise This Shape)

For any "ASG not scaling" ticket, the order is always:

1. **Confirm the alarm is actually in ALARM state.** (Ticket could be wrong.)
2. **Check `min/max/desired` on the ASG.** If `max == desired`, stop — that's your bug.
3. **Read the scaling policy.** `ExactCapacity` + small number is almost always wrong for scale-up.
4. **Check the alarm's `alarm_actions`** points at the right policy ARN. (Not broken in this lab, but check it anyway.)
5. **Check cooldown.** A 1-hour cooldown will look like "nothing is happening" for 59 minutes.
6. **Find the Terraform, fix it there, validate, plan, apply, re-verify against AWS.**

---

## Lab vs Real Life

- **Target tracking is the modern default.** In production, you'd use `target_tracking_configuration` with `ASGAverageCPUUtilization` at 70. AWS manages scale-up *and* scale-down automatically. Step policies like this lab are older-style and more fiddly.
- **You need a scale-down policy too.** This lab only scales up. Without a matching scale-down, you'll pay for instances forever after the spike passes.
- **`health_check_type = "EC2"` only checks the hypervisor.** Behind an ALB, use `"ELB"` so the app being broken also triggers replacement.
- **Warm pools** help when instance boot is slow (heavy AMIs, long user-data scripts).
- **Don't test scaling in prod.** Use `stress-ng` or AWS Fault Injection Simulator in staging.

---

## Key Concepts

- `max_size` is a hard ceiling. The ASG will never exceed it. If `max == desired`, scaling up is impossible.
- `ExactCapacity` sets an absolute number. `ChangeInCapacity` adds/removes relative to current. They are not interchangeable.
- CloudWatch alarms don't scale anything themselves — they trigger *policies*, which act on the ASG.
- The AWS API is the source of truth for current state. Terraform is the source of truth for desired state. When they disagree, one of them is wrong — figure out which before you fix anything.
