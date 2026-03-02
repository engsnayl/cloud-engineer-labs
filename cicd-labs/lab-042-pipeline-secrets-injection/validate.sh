#!/bin/bash
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

grep -q "AWS_ACCESS_KEY_ID" Dockerfile 2>/dev/null
[[ $? -ne 0 ]]
check "Dockerfile doesn't contain AWS credentials" "$?"

grep -q "AWS_SECRET_ACCESS_KEY" Dockerfile 2>/dev/null
[[ $? -ne 0 ]]
check "No secret access key in Dockerfile" "$?"

grep -q "build-arg.*SECRET\|build-arg.*ACCESS_KEY" .github/workflows/deploy.yml 2>/dev/null
[[ $? -ne 0 ]]
check "No secrets passed as Docker build args" "$?"

grep -q "AWS_ACCESS_KEY_ID" .github/workflows/deploy.yml 2>/dev/null
check "Workflow uses standard AWS credential names" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
