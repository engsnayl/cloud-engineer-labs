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

# ---- Check 1: Workflow file exists ----
test -f .github/workflows/ci.yml
check "Workflow file exists at .github/workflows/ci.yml" "$?"

# ---- Check 2: Triggers include push and pull_request ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -q "push:" .github/workflows/ci.yml && grep -q "pull_request:" .github/workflows/ci.yml
    check "Workflow triggers on both push and pull_request" "$?"
else
    check "Workflow triggers on both push and pull_request" "1"
fi

# ---- Check 3: Lint stage exists ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -qE "npm run lint|eslint" .github/workflows/ci.yml
    check "Pipeline includes a lint step" "$?"
else
    check "Pipeline includes a lint step" "1"
fi

# ---- Check 4: Test stage exists ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -qE "npm run test|npm test|jest" .github/workflows/ci.yml
    check "Pipeline includes a test step" "$?"
else
    check "Pipeline includes a test step" "1"
fi

# ---- Check 5: Docker build with SHA tag ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -qE "docker build" .github/workflows/ci.yml && grep -qE "github\.sha|GITHUB_SHA" .github/workflows/ci.yml
    check "Pipeline builds Docker image tagged with git SHA" "$?"
else
    check "Pipeline builds Docker image tagged with git SHA" "1"
fi

# ---- Check 6: Deploy is conditional on main branch ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -qE "if:.*github\.(event_name|ref).*main" .github/workflows/ci.yml
    check "Deploy stage is conditional (main branch only)" "$?"
else
    check "Deploy stage is conditional (main branch only)" "1"
fi

# ---- Check 7: Smoke test / health check exists ----
if [[ -f .github/workflows/ci.yml ]]; then
    grep -qE "health|smoke|curl|wget" .github/workflows/ci.yml
    check "Pipeline includes a post-deploy health/smoke check" "$?"
else
    check "Pipeline includes a post-deploy health/smoke check" "1"
fi

# ---- Check 8: Deploy script exists and is executable ----
test -x deploy.sh
check "deploy.sh exists and is executable" "$?"

# ---- Check 9: Deploy script uses versioned tags (not just latest) ----
if [[ -f deploy.sh ]]; then
    grep -qE '\$1|\$\{1|\$TAG|\$VERSION|\$IMAGE_TAG|\$SHA' deploy.sh && ! grep -q 'docker pull.*:latest' deploy.sh
    check "deploy.sh accepts a version parameter (not hardcoded latest)" "$?"
else
    check "deploy.sh accepts a version parameter (not hardcoded latest)" "1"
fi

# ---- Check 10: Deploy script includes health check ----
if [[ -f deploy.sh ]]; then
    grep -qE "health|curl|wget" deploy.sh
    check "deploy.sh includes a health check after starting container" "$?"
else
    check "deploy.sh includes a health check after starting container" "1"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
