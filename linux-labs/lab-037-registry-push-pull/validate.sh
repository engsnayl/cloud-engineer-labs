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

curl -s http://localhost:5000/v2/_catalog 2>/dev/null | grep -q "myapp"
check "Image 'myapp' exists in local registry" "$?"

docker pull localhost:5000/myapp:latest &>/dev/null
check "Can pull image from localhost:5000" "$?"

docker image inspect localhost:5000/myapp:latest &>/dev/null
check "Image 'localhost:5000/myapp:latest' exists locally" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
