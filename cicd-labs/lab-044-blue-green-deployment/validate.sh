#!/bin/bash
# Lab 044 — Blue-Green Deployment Validator
# Verifies switch.sh actually performs a working blue-green switch, not just contains the right keywords.

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

# -----------------------------------------------------------------------------
# Section 1 — Pre-flight: required files exist and are sane
# -----------------------------------------------------------------------------
echo "── Pre-flight ──"

test -f switch.sh
check "switch.sh exists" "$?"

test -x switch.sh
check "switch.sh is executable" "$?"

test -f nginx.conf
check "nginx.conf exists" "$?"

test -f docker-compose.yml
check "docker-compose.yml exists" "$?"

# -----------------------------------------------------------------------------
# Section 2 — Lightweight static checks (cheap signals before we run anything)
# -----------------------------------------------------------------------------
echo ""
echo "── Static checks ──"

grep -qE "health|curl|wget" switch.sh 2>/dev/null
check "Script appears to perform a health check (curl/wget/health)" "$?"

grep -qE "nginx.*reload|nginx.*-s" switch.sh 2>/dev/null
check "Script appears to reload nginx" "$?"

grep -qE "blue|green" switch.sh 2>/dev/null
check "Script references blue/green environments" "$?"

# -----------------------------------------------------------------------------
# Section 3 — Pre-flight: the lab environment is up
# (Behavioural checks below assume the compose stack is running)
# -----------------------------------------------------------------------------
echo ""
echo "── Lab environment ──"

# Check all three services are running
BLUE_UP=$(docker compose ps --status running --services 2>/dev/null | grep -c '^app-blue$')
GREEN_UP=$(docker compose ps --status running --services 2>/dev/null | grep -c '^app-green$')
ROUTER_UP=$(docker compose ps --status running --services 2>/dev/null | grep -c '^router$')

[[ "$BLUE_UP" == "1" ]]
check "app-blue container is running" "$?"

[[ "$GREEN_UP" == "1" ]]
check "app-green container is running" "$?"

[[ "$ROUTER_UP" == "1" ]]
check "router container is running" "$?"

# If the environment isn't up, behavioural tests are meaningless — bail with guidance
if [[ "$BLUE_UP" != "1" || "$GREEN_UP" != "1" || "$ROUTER_UP" != "1" ]]; then
    echo ""
    echo "⚠️   Skipping behavioural tests — containers are not all running."
    echo "    Run 'docker compose up -d' first, then re-run validation."
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi

# Confirm both backends are reachable directly (so the switch script has working targets)
curl -sf --max-time 3 http://localhost:8001/ > /dev/null 2>&1
check "app-blue responds on port 8001" "$?"

curl -sf --max-time 3 http://localhost:8002/ > /dev/null 2>&1
check "app-green responds on port 8002" "$?"

curl -sf --max-time 3 http://localhost/ > /dev/null 2>&1
check "router responds on port 80" "$?"

# -----------------------------------------------------------------------------
# Section 4 — Behavioural: run the switch and verify it actually switched
# -----------------------------------------------------------------------------
echo ""
echo "── Behavioural switch test ──"

# Capture starting state from nginx.conf
if grep -q "app-blue" nginx.conf; then
    START_ENV="blue"
    EXPECTED_AFTER_FIRST_SWITCH="green"
elif grep -q "app-green" nginx.conf; then
    START_ENV="green"
    EXPECTED_AFTER_FIRST_SWITCH="blue"
else
    START_ENV="unknown"
    EXPECTED_AFTER_FIRST_SWITCH="unknown"
fi

[[ "$START_ENV" != "unknown" ]]
check "nginx.conf points at a known upstream before switch ($START_ENV)" "$?"

# Run the switch script
./switch.sh > /tmp/switch-output-1.log 2>&1
SWITCH_EXIT=$?

[[ "$SWITCH_EXIT" == "0" ]]
check "switch.sh exits 0 on first run" "$?"

# Verify nginx.conf now points at the OTHER environment
if grep -q "app-$EXPECTED_AFTER_FIRST_SWITCH" nginx.conf; then
    NGINX_FLIPPED=0
else
    NGINX_FLIPPED=1
fi
check "nginx.conf now points at app-$EXPECTED_AFTER_FIRST_SWITCH after switch" "$NGINX_FLIPPED"

# Verify traffic actually moves — port 80 should now match the target backend's response
# We compare the response from port 80 with the response from the target backend's direct port
if [[ "$EXPECTED_AFTER_FIRST_SWITCH" == "green" ]]; then
    TARGET_PORT=8002
else
    TARGET_PORT=8001
fi

# Give nginx a moment to finish reloading
sleep 1

ROUTER_RESPONSE=$(curl -s --max-time 3 http://localhost/ 2>/dev/null)
TARGET_RESPONSE=$(curl -s --max-time 3 http://localhost:$TARGET_PORT/ 2>/dev/null)

if [[ -n "$ROUTER_RESPONSE" && "$ROUTER_RESPONSE" == "$TARGET_RESPONSE" ]]; then
    TRAFFIC_MOVED=0
else
    TRAFFIC_MOVED=1
fi
check "Traffic on port 80 now matches app-$EXPECTED_AFTER_FIRST_SWITCH" "$TRAFFIC_MOVED"

# -----------------------------------------------------------------------------
# Section 5 — Behavioural: rollback works (running again flips back)
# -----------------------------------------------------------------------------
echo ""
echo "── Rollback test (script is its own rollback) ──"

./switch.sh > /tmp/switch-output-2.log 2>&1
ROLLBACK_EXIT=$?

[[ "$ROLLBACK_EXIT" == "0" ]]
check "switch.sh exits 0 on second run (rollback)" "$?"

# After running twice, we should be back to the starting environment
if grep -q "app-$START_ENV" nginx.conf; then
    NGINX_RESTORED=0
else
    NGINX_RESTORED=1
fi
check "nginx.conf restored to app-$START_ENV after second run" "$NGINX_RESTORED"

if [[ "$START_ENV" == "blue" ]]; then
    ROLLBACK_PORT=8001
else
    ROLLBACK_PORT=8002
fi

sleep 1

ROUTER_RESPONSE_AFTER=$(curl -s --max-time 3 http://localhost/ 2>/dev/null)
ROLLBACK_RESPONSE=$(curl -s --max-time 3 http://localhost:$ROLLBACK_PORT/ 2>/dev/null)

if [[ -n "$ROUTER_RESPONSE_AFTER" && "$ROUTER_RESPONSE_AFTER" == "$ROLLBACK_RESPONSE" ]]; then
    ROLLBACK_TRAFFIC=0
else
    ROLLBACK_TRAFFIC=1
fi
check "Traffic on port 80 returns to app-$START_ENV after rollback" "$ROLLBACK_TRAFFIC"

# -----------------------------------------------------------------------------
# Section 6 — Safety: aborts when target is unhealthy
# -----------------------------------------------------------------------------
echo ""
echo "── Safety test (refuses to switch to an unhealthy target) ──"

# Identify which env we'd switch TO from the current state, and stop it
if grep -q "app-blue" nginx.conf; then
    UNHEALTHY_TARGET="app-green"
    HEALTHY_CURRENT="blue"
else
    UNHEALTHY_TARGET="app-blue"
    HEALTHY_CURRENT="green"
fi

# Stop the target so health checks should fail
docker compose stop "$UNHEALTHY_TARGET" > /dev/null 2>&1
sleep 2

./switch.sh > /tmp/switch-output-3.log 2>&1
UNHEALTHY_EXIT=$?

# Restart the stopped service so the lab is left in a usable state
docker compose start "$UNHEALTHY_TARGET" > /dev/null 2>&1

# A safe script should exit non-zero when the target is unhealthy
[[ "$UNHEALTHY_EXIT" != "0" ]]
check "switch.sh exits non-zero when target is unhealthy" "$?"

# And nginx.conf should NOT have been changed
if grep -q "app-$HEALTHY_CURRENT" nginx.conf; then
    CONFIG_PROTECTED=0
else
    CONFIG_PROTECTED=1
fi
check "nginx.conf was NOT modified when target was unhealthy" "$CONFIG_PROTECTED"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Tip: switch script output captured at /tmp/switch-output-{1,2,3}.log"
fi

[[ "$FAIL" -eq 0 ]]
