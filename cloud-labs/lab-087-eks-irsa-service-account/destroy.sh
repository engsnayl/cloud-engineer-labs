#!/bin/bash
# Lab 087 — Safe teardown wrapper
# Deletes K8s resources, empties S3, runs terraform destroy, verifies nothing is left.

set -e

echo ""
echo "=== Lab 087 Teardown ==="
echo ""

REGION=$(terraform output -raw region 2>/dev/null || echo "eu-west-2")
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")

# --- Step 1: Delete K8s resources ---
if [[ -n "$CLUSTER_NAME" ]]; then
  echo "[1/4] Deleting Kubernetes resources..."
  kubectl delete -f manifests/ --ignore-not-found=true 2>/dev/null || true
else
  echo "[1/4] No cluster in state — skipping kubectl delete"
fi

# --- Step 2: Empty S3 bucket (terraform destroy fails if non-empty) ---
if [[ -n "$BUCKET" ]]; then
  echo "[2/4] Emptying S3 bucket $BUCKET..."
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" 2>/dev/null || true
else
  echo "[2/4] No S3 bucket in state — skipping"
fi

# --- Step 3: Terraform destroy ---
echo "[3/4] Running terraform destroy..."
terraform destroy -auto-approve

# --- Step 4: Verify nothing is left costing money ---
echo ""
echo "[4/4] Verifying no expensive resources remain..."
echo ""

CLUSTERS=$(aws eks list-clusters --region "$REGION" --query 'clusters[?contains(@, `lab-087`)]' --output text)
if [[ -z "$CLUSTERS" ]]; then
  echo "  ✅  No EKS clusters remain"
else
  echo "  ❌  EKS clusters still exist: $CLUSTERS"
fi

NATS=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=state,Values=available,pending" --query 'NatGateways[].NatGatewayId' --output text)
if [[ -z "$NATS" ]]; then
  echo "  ✅  No NAT Gateways remain"
else
  echo "  ⚠️   NAT Gateways still exist: $NATS"
  echo "      (These may belong to other labs — check before manually deleting)"
fi

OIDC=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'eks.$REGION')]" --output text)
if [[ -z "$OIDC" ]]; then
  echo "  ✅  No EKS OIDC providers remain"
else
  echo "  ⚠️   OIDC providers still exist: $OIDC"
fi

echo ""
echo "Teardown complete. If any ⚠️ appeared above, investigate before closing the laptop."
echo ""
