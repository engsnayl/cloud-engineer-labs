#!/bin/bash
echo "Running CloudFormation validation..."
echo ""
PASS=0; FAIL=0
check() { local d="$1" r="$2"; if [[ "$r" == "0" ]]; then echo -e "  ✅  $d"; ((PASS++)); else echo -e "  ❌  $d"; ((FAIL++)); fi; }

# Check template syntax
aws cloudformation validate-template --template-body file://template.yaml &>/dev/null
check "CloudFormation template is valid" "$?"

echo ""; echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
