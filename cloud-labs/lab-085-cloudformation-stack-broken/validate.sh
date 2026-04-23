#!/bin/bash
# Lab 085 - CloudFormation Stack Failed - validation script
# Checks that the three real bugs in template.yaml have been fixed.
# Does NOT deploy - this is static analysis only. For a full deploy test,
# run `aws cloudformation create-stack` manually per the solution file.

set +e

echo "Running CloudFormation validation..."
echo ""
PASS=0; FAIL=0

check() {
  local d="$1" r="$2"
  if [[ "$r" == "0" ]]; then
    echo -e "  ✅  $d"
    ((PASS++))
  else
    echo -e "  ❌  $d"
    ((FAIL++))
  fi
}

REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
TEMPLATE="template.yaml"

# 0. Sanity — template file exists
if [[ ! -f "$TEMPLATE" ]]; then
  echo "  ❌  $TEMPLATE not found in current directory"
  exit 1
fi

# 1. Template is structurally valid
aws cloudformation validate-template --template-body "file://$TEMPLATE" --region "$REGION" &>/dev/null
check "CloudFormation validate-template passes" "$?"

# 2. Bug 1 — !Ref with ${...} interpolation must be gone (should be !Sub)
if grep -qE '!Ref[[:space:]]+"\$\{' "$TEMPLATE"; then
  check "Bug 1 fixed: no !Ref wrapping \${...} interpolation" "1"
else
  check "Bug 1 fixed: no !Ref wrapping \${...} interpolation" "0"
fi

# 3. Bug 1 (positive) — at least one !Sub with interpolation present
if grep -qE '!Sub[[:space:]]+"\$\{' "$TEMPLATE"; then
  check "Bug 1 fixed: !Sub used for string interpolation" "0"
else
  check "Bug 1 fixed: !Sub used for string interpolation" "1"
fi

# 4. Bug 4 — ImageId property present on WebInstance
if grep -qE '^[[:space:]]+ImageId:' "$TEMPLATE"; then
  check "Bug 4 fixed: ImageId property present" "0"
else
  check "Bug 4 fixed: ImageId property present" "1"
fi

# 5. Bug 4 (positive) — SSM parameter used for AMI (industry best practice)
if grep -qE 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>' "$TEMPLATE"; then
  check "Bug 4 fixed: SSM parameter used for AMI lookup" "0"
else
  check "Bug 4 fixed: SSM parameter used for AMI lookup" "1"
fi

# 6. Bug 5 — IpAddress must be gone from Outputs
if grep -q 'WebInstance\.IpAddress' "$TEMPLATE"; then
  check "Bug 5 fixed: WebInstance.IpAddress removed" "1"
else
  check "Bug 5 fixed: WebInstance.IpAddress removed" "0"
fi

# 7. Bug 5 (positive) — correct PublicIp attribute used
if grep -q 'WebInstance\.PublicIp' "$TEMPLATE"; then
  check "Bug 5 fixed: WebInstance.PublicIp used in Outputs" "0"
else
  check "Bug 5 fixed: WebInstance.PublicIp used in Outputs" "1"
fi

# 8. Regression check — no leftover '# BUG' comments that would spoil the learner
if grep -q '# BUG' "$TEMPLATE"; then
  check "No '# BUG' hint comments in template (they spoil the lab)" "1"
else
  check "No '# BUG' hint comments in template (they spoil the lab)" "0"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "🎉  Template looks good. Ready to run:"
  echo ""
  echo "    aws cloudformation create-stack \\"
  echo "      --stack-name lab-085 \\"
  echo "      --template-body file://template.yaml \\"
  echo "      --region $REGION"
  echo ""
  echo "Remember to destroy when done:"
  echo ""
  echo "    aws cloudformation delete-stack --stack-name lab-085 --region $REGION"
  echo "    aws cloudformation wait stack-delete-complete --stack-name lab-085 --region $REGION"
  exit 0
else
  exit 1
fi
