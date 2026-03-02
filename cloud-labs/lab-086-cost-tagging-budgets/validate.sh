#!/bin/bash
echo "Running terraform validation..."
echo ""
PASS=0; FAIL=0
check() { local d="$1" r="$2"; if [[ "$r" == "0" ]]; then echo -e "  ✅  $d"; ((PASS++)); else echo -e "  ❌  $d"; ((FAIL++)); fi; }
terraform validate &>/dev/null; check "Terraform configuration is valid" "$?"
terraform plan -detailed-exitcode &>/dev/null; plan_exit=$?; [[ "$plan_exit" -ne 1 ]]; check "Terraform plan completes without errors" "$?"
echo ""; echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]
