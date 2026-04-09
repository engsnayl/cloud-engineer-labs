#!/bin/bash
# =============================================================================
# Lab 072 — Terraform Workspace Confusion
# Setup Script — run this once after cd into the lab directory
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}Setting up Lab 072 — Terraform Workspace Confusion...${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────────${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Initialise Terraform if not already done
# -----------------------------------------------------------------------------
if [[ ! -d ".terraform" ]]; then
    echo -e "${YELLOW}Running terraform init...${NC}"
    terraform init -input=false
    echo ""
else
    echo -e "${GREEN}✔ Terraform already initialised${NC}"
fi

# -----------------------------------------------------------------------------
# Step 2: Clean up any leftover workspaces from a previous attempt
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Cleaning up any existing workspaces...${NC}"

# Must be in default to delete other workspaces
terraform workspace select default 2>/dev/null || true

for ws in staging production; do
    if terraform workspace list | grep -q "^  $ws$"; then
        echo -e "  Removing workspace: $ws"
        terraform workspace delete "$ws" 2>/dev/null || true
    fi
done

# -----------------------------------------------------------------------------
# Step 3: Clean up any leftover state files from previous attempts
# -----------------------------------------------------------------------------
if [[ -d "terraform.tfstate.d" ]]; then
    echo -e "${YELLOW}Removing stale state directory...${NC}"
    rm -rf terraform.tfstate.d
fi

if [[ -f "terraform.tfstate" ]]; then
    echo -e "${YELLOW}Removing stale state file...${NC}"
    rm -f terraform.tfstate terraform.tfstate.backup
fi

# -----------------------------------------------------------------------------
# Step 4: Create the staging and production workspaces
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Creating workspaces...${NC}"

terraform workspace new staging
echo -e "  ${GREEN}✔ Created workspace: staging${NC}"

terraform workspace new production
echo -e "  ${GREEN}✔ Created workspace: production${NC}"

# -----------------------------------------------------------------------------
# Step 5: Return to default workspace
# The learner should discover and select workspaces themselves
# -----------------------------------------------------------------------------
terraform workspace select default
echo -e "  ${GREEN}✔ Returned to default workspace${NC}"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}Lab environment ready.${NC}"
echo ""
echo -e "  Workspaces created: ${BOLD}staging${NC}, ${BOLD}production${NC}"
echo -e "  Active workspace:   ${BOLD}default${NC}"
echo ""
echo -e "Start by reviewing the Terraform files in this directory,"
echo -e "then work through the incident ticket in CHALLENGE.md."
echo ""
