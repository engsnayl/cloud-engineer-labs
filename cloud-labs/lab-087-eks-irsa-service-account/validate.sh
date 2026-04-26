#!/bin/bash
# Lab 087 — EKS IRSA validator
# Checks the full IRSA chain end-to-end: Terraform config, AWS IAM, K8s manifests,
# and the pod's actual ability to call S3 and DynamoDB.

set -o pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  local rc="$2"
  if [[ "$rc" == "0" ]]; then
    echo -e "  \e[32m✅\e[0m  $desc"
    PASS=$((PASS+1))
  else
    echo -e "  \e[31m❌\e[0m  $desc"
    FAIL=$((FAIL+1))
  fi
}

echo ""
echo "=== Lab 087: EKS IRSA Validator ==="
echo ""

# --- 1. Terraform config sanity ---
echo "[1/4] Terraform configuration"
terraform validate &>/dev/null
check "terraform validate passes" "$?"

# --- 2. OIDC provider client ID ---
echo ""
echo "[2/4] IAM / OIDC configuration"

# Check client_id_list contains sts.amazonaws.com (not ec2.amazonaws.com)
# Query AWS directly rather than parsing terraform state (which formats client_id_list across multiple lines)
OIDC_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'eks.eu-west-2')].Arn" --output text 2>/dev/null | head -n1)
if [[ -n "$OIDC_ARN" ]]; then
  CLIENT_IDS=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" --query 'ClientIDList' --output text 2>/dev/null)
  if echo "$CLIENT_IDS" | grep -qw 'sts.amazonaws.com'; then
    check "OIDC client_id_list contains sts.amazonaws.com" "0"
  else
    check "OIDC client_id_list contains sts.amazonaws.com" "1"
  fi
else
  check "OIDC client_id_list contains sts.amazonaws.com" "1"
fi

# Check trust policy uses real OIDC issuer URL (not literal "oidc.eks:")
ROLE_NAME="eks-app-role"
TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)
if [[ -n "$TRUST_POLICY" ]]; then
  if echo "$TRUST_POLICY" | grep -qE 'oidc\.eks\.[a-z0-9-]+\.amazonaws\.com'; then
    check "Trust policy uses real OIDC issuer URL" "0"
  else
    check "Trust policy uses real OIDC issuer URL" "1"
  fi

  if echo "$TRUST_POLICY" | grep -q '"sts.amazonaws.com"'; then
    check "Trust policy aud condition set to sts.amazonaws.com" "0"
  else
    check "Trust policy aud condition set to sts.amazonaws.com" "1"
  fi
else
  check "Trust policy uses real OIDC issuer URL" "1"
  check "Trust policy aud condition set to sts.amazonaws.com" "1"
fi

# Check IAM policy resources are scoped (not "*")
POLICY_DOC=$(aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name app-permissions --query 'PolicyDocument' --output json 2>/dev/null)
if [[ -n "$POLICY_DOC" ]]; then
  WILDCARD_COUNT=$(echo "$POLICY_DOC" | grep -c '"Resource": "\*"')
  if [[ "$WILDCARD_COUNT" -eq 0 ]]; then
    check "IAM policy has no wildcard (*) resources" "0"
  else
    check "IAM policy has no wildcard (*) resources" "1"
  fi
else
  check "IAM policy has no wildcard (*) resources" "1"
fi

# --- 3. Kubernetes service account ---
echo ""
echo "[3/4] Kubernetes service account and pod"

SA_ANNOTATION=$(kubectl get serviceaccount app-service-account -n default -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
if [[ -n "$SA_ANNOTATION" ]]; then
  check "ServiceAccount has eks.amazonaws.com/role-arn annotation" "0"
else
  check "ServiceAccount has eks.amazonaws.com/role-arn annotation" "1"
fi

POD_SA=$(kubectl get pod app-pod -n default -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null)
if [[ "$POD_SA" == "app-service-account" ]]; then
  check "Pod uses app-service-account (not default)" "0"
else
  check "Pod uses app-service-account (not default)" "1"
fi

# --- 4. Live functional test ---
echo ""
echo "[4/4] Pod can actually call AWS APIs"

POD_STATUS=$(kubectl get pod app-pod -n default -o jsonpath='{.status.phase}' 2>/dev/null)
if [[ "$POD_STATUS" == "Running" ]]; then
  check "Pod is Running" "0"

  # Get last 30 lines of pod logs
  LOGS=$(kubectl logs app-pod -n default --tail=50 2>/dev/null)

  if echo "$LOGS" | grep -q "test-object.txt"; then
    check "Pod successfully lists S3 bucket contents" "0"
  else
    check "Pod successfully lists S3 bucket contents" "1"
  fi

  if echo "$LOGS" | grep -q '"hello from irsa lab"'; then
    check "Pod successfully reads DynamoDB item" "0"
  else
    check "Pod successfully reads DynamoDB item" "1"
  fi

  if echo "$LOGS" | grep -qE "Unable to locate credentials|AccessDenied|WebIdentityErr"; then
    check "Pod has no credential errors in recent logs" "1"
  else
    check "Pod has no credential errors in recent logs" "0"
  fi
else
  check "Pod is Running" "1"
  check "Pod successfully lists S3 bucket contents" "1"
  check "Pod successfully reads DynamoDB item" "1"
  check "Pod has no credential errors in recent logs" "1"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "🎉 All checks passed. Don't forget to run ./destroy.sh when finished."
  exit 0
else
  echo "Some checks failed — keep debugging."
  exit 1
fi
