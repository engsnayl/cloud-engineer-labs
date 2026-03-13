#!/bin/bash
# corrupt-state.sh
# Simulates what happens when someone manually deletes a resource in the AWS
# console without going through Terraform.
#
# In the real world: an engineer logs into the console and deletes the
# security group directly. Terraform's state file still thinks it exists.
# The next time you run terraform plan, Terraform tries to read the SG
# from AWS and gets nothing back — because it's gone.
#
# This script replicates that scenario by removing the security group
# entry from Terraform's state file.

set -e

echo ""
echo "================================================"
echo " Simulating manual console deletion..."
echo " Someone just deleted the security group in AWS."
echo "================================================"
echo ""

# Check we have a state file to work with
if [ ! -f "terraform.tfstate" ]; then
  echo "ERROR: No terraform.tfstate found."
  echo "Make sure you have run: cp terraform.tfstate.bak terraform.tfstate"
  echo "or that the state file is present in this directory."
  exit 1
fi

# Remove the security group from state, simulating it being deleted in the console
terraform state rm aws_security_group.app

echo ""
echo "================================================"
echo " Done. The security group no longer exists in"
echo " AWS — but Terraform's config still defines it."
echo ""
echo " Run: terraform plan"
echo " Observe the error, then work out how to fix it."
echo "================================================"
echo ""
