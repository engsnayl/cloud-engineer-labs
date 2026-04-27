#!/bin/bash
# validate.sh — Lab 043 (deployment rollback)
#
# Each check is deliberately specific. A naive script that satisfies the
# letter of the brief without actually working should fail at least one
# check.

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

echo "Running validation checks..."
echo ""

# Check 1: Performs a health check. Two-part test: there's a curl call
# that isn't inside a comment, AND somewhere the script references a
# health URL/endpoint. This stops a script that just sprinkles "curl"
# in comments from passing.
grep -qE '^[[:space:]]*[^#]*curl' deploy.sh 2>/dev/null && \
    grep -qiE '(health|/healthz|HEALTH_URL)' deploy.sh 2>/dev/null
check "Deploy script performs an HTTP health check (curl)" "$?"

# Check 2: Rollback. Must reference both the concept (rollback/previous)
# AND have a docker run elsewhere using a captured variable, so a script
# that just has the word "rollback" in a comment doesn't pass.
grep -qiE 'rollback|previous|revert' deploy.sh 2>/dev/null && \
    grep -qE 'docker[[:space:]]+run.*\$' deploy.sh 2>/dev/null
check "Deploy script implements rollback (references previous + redeploys)" "$?"

# Check 3: Image tag uses a version variable. Look for myapp:$VAR style
# or any image:variable interpolation. A script that hardcodes
# "myapp:latest" will fail here.
grep -qE 'docker[[:space:]]+run.*:\$[A-Z_a-z]+' deploy.sh 2>/dev/null
check "Deploy script uses a version variable in the image tag" "$?"

# Check 4: Accepts version as a CLI argument. Look for $1 being assigned
# (not just appearing somewhere) — most idiomatic patterns: VERSION=$1
# or VERSION=${1...}. Also accept VERSION="$1".
grep -qE '^[[:space:]]*VERSION=("?\$\{?1)' deploy.sh 2>/dev/null
check "Deploy script accepts version as the first argument (\$1)" "$?"

# Bonus checks — informational, not counted as failures, just visibility.
echo ""
echo "Bonus / quality checks:"

if grep -qE 'exit[[:space:]]+1' deploy.sh 2>/dev/null; then
    echo "  ✅  Script signals failure with exit 1"
else
    echo "  ⚠️   Script may not exit non-zero on failure (CI/CD wouldn't know to alert)"
fi

if grep -qE '(for[[:space:]]+.*seq|while.*\[.*-lt|MAX_RETRIES|retries?)' deploy.sh 2>/dev/null; then
    echo "  ✅  Health check appears to retry (good — apps need startup time)"
else
    echo "  ⚠️   Health check may not retry — apps usually need a few seconds to start"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
