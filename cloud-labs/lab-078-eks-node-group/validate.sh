#!/bin/bash
echo "Running Lab 078 validation — EKS Node Group..."
echo ""

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        ((FAIL++))
    fi
}

# ── Check 1: Terraform syntax is valid ─────────────────────────────────────
terraform validate &>/dev/null
check "Terraform configuration is valid (syntax)" "$?"

# ── Check 2: Terraform plan completes without errors ───────────────────────
terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# ── Check 3: A separate node IAM role exists (not just the cluster role) ───
# The fix requires an aws_iam_role resource that is NOT the cluster role.
# We look for an iam_role resource whose name is not "cluster".
node_role_count=$(grep -c 'resource "aws_iam_role"' main.tf 2>/dev/null || echo 0)
[[ "$node_role_count" -ge 2 ]]
check "A dedicated node IAM role resource exists (separate from the cluster role)" "$?"

# ── Check 4: Node group references the node role, not the cluster role ─────
# The broken state has: node_role_arn = aws_iam_role.cluster.arn
# The fix should have:  node_role_arn = aws_iam_role.node.arn
grep -q 'node_role_arn.*aws_iam_role\.node\.arn' main.tf 2>/dev/null
check "Node group node_role_arn references the node role (not the cluster role)" "$?"

# ── Check 5: Node role trusts ec2.amazonaws.com ────────────────────────────
# The cluster role trusts eks.amazonaws.com — the node role must trust ec2.
grep -q 'ec2\.amazonaws\.com' main.tf 2>/dev/null
check "Node IAM role trust policy includes ec2.amazonaws.com" "$?"

# ── Check 6: All three required managed policies are attached ──────────────
grep -q 'AmazonEKSWorkerNodePolicy' main.tf 2>/dev/null
check "AmazonEKSWorkerNodePolicy is attached to the node role" "$?"

grep -q 'AmazonEKS_CNI_Policy' main.tf 2>/dev/null
check "AmazonEKS_CNI_Policy is attached to the node role" "$?"

grep -q 'AmazonEC2ContainerRegistryReadOnly' main.tf 2>/dev/null
check "AmazonEC2ContainerRegistryReadOnly is attached to the node role" "$?"

# ── Check 7: instance_types is declared on the node group ──────────────────
grep -q 'instance_types' main.tf 2>/dev/null
check "Node group declares instance_types explicitly" "$?"

# ── Check 8: depends_on is present on the node group ──────────────────────
grep -q 'depends_on' main.tf 2>/dev/null
check "Node group has depends_on for IAM policy attachments" "$?"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
