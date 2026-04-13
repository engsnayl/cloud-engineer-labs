#!/bin/bash
# =============================================================================
# Lab 076 — Route 53 DNS Failover Not Working
# setup.sh — Run this immediately after cd-ing into the lab directory
# This script confirms your environment is ready and presents the incident ticket
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Lab 076 — Route 53 DNS Failover Not Working         ║${NC}"
echo -e "${CYAN}║                     Environment Setup                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Check 1: AWS CLI available
# =============================================================================
echo -e "${WHITE}[1/4] Checking AWS CLI...${NC}"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found. Install it before continuing.${NC}"
    exit 1
fi
AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
echo -e "${GREEN}✓ AWS CLI found: ${AWS_VERSION}${NC}"

# =============================================================================
# Check 2: AWS credentials configured and working
# =============================================================================
echo -e "${WHITE}[2/4] Checking AWS credentials...${NC}"
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ AWS credentials not working. Run 'aws configure' or check your IAM user.${NC}"
    echo -e "${RED}  Error: ${CALLER_IDENTITY}${NC}"
    exit 1
fi
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
IAM_USER=$(echo "$CALLER_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
echo -e "${GREEN}✓ Credentials valid${NC}"
echo -e "  Account : ${ACCOUNT_ID}"
echo -e "  Identity: ${IAM_USER}"

# =============================================================================
# Check 3: Terraform available
# =============================================================================
echo -e "${WHITE}[3/4] Checking Terraform...${NC}"
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Terraform not found. Check your PATH or reinstall.${NC}"
    exit 1
fi
TF_VERSION=$(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || terraform version | head -1)
echo -e "${GREEN}✓ Terraform found: ${TF_VERSION}${NC}"

# =============================================================================
# Check 4: Required lab files present
# =============================================================================
echo -e "${WHITE}[4/4] Checking lab files...${NC}"
MISSING=0
for f in main.tf validate.sh; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}✗ Missing: $f${NC}"
        MISSING=1
    else
        echo -e "${GREEN}✓ Found: $f${NC}"
    fi
done

if [ $MISSING -eq 1 ]; then
    echo -e "${RED}One or more required files are missing. Run 'git pull' and try again.${NC}"
    exit 1
fi

# =============================================================================
# Print the incident ticket
# =============================================================================
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ⚠  INCIDENT TICKET — HANDLE WITH PRIORITY                   ${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WHITE}  Ticket ID  :${NC} INCIDENT-AWS-008"
echo -e "${WHITE}  Severity   :${NC} ${RED}P1 — Full customer-facing outage${NC}"
echo -e "${WHITE}  Reported   :${NC} 03:47 UTC"
echo -e "${WHITE}  Assigned to:${NC} You"
echo ""
echo -e "${WHITE}  Summary:${NC}"
echo "    Primary region went down. Route 53 was supposed to automatically"
echo "    fail over DNS traffic to the secondary region. It didn't."
echo "    DNS is still resolving to the unhealthy primary endpoint."
echo "    Customers cannot reach the service."
echo ""
echo -e "${WHITE}  Background:${NC}"
echo "    The Route 53 failover policy was configured as part of last quarter's"
echo "    disaster recovery work. It has never been tested under real conditions."
echo "    On-call flagged that health checks may not be correctly set up."
echo ""
echo -e "${WHITE}  Expected behaviour:${NC}"
echo "    When primary (10.0.1.100) is unhealthy, Route 53 should serve"
echo "    the secondary IP (10.1.1.100) within 60 seconds."
echo ""
echo -e "${WHITE}  Actual behaviour:${NC}"
echo "    Route 53 continues to serve the primary IP regardless of health."
echo "    Secondary IP is never returned."
echo ""
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Remind to read the solution file
# =============================================================================
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Read the incident ticket above carefully"
echo "  2. Run:  terraform init"
echo "  3. Run:  terraform apply -auto-approve   (deploys the broken state)"
echo "  4. Follow the solution walkthrough"
echo "  5. When done: terraform destroy -auto-approve"
echo ""
echo -e "${GREEN}Environment ready. Good luck.${NC}"
echo ""
