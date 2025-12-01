#!/bin/bash
#
# GCloud Pre-Flight Checks
# Validates that gcloud CLI is installed and authenticated before VM provisioning
#
# Usage: ./gcloud_prechecks.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  GCloud Pre-Flight Checks${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

# Check 1: gcloud executable exists
echo -n "Checking gcloud installation... "
if command -v gcloud &> /dev/null; then
    GCLOUD_PATH=$(which gcloud)
    echo -e "${GREEN}✓ Found${NC} at $GCLOUD_PATH"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo "  Install: https://cloud.google.com/sdk/docs/install"
    ((CHECKS_FAILED++))
fi

# Check 2: Authentication status
echo -n "Checking gcloud authentication... "
if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
    echo -e "${GREEN}✓ Authenticated${NC} as $ACTIVE_ACCOUNT"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ NOT AUTHENTICATED${NC}"
    echo "  Run: gcloud auth login"
    ((CHECKS_FAILED++))
fi

# Check 3: Project access
echo -n "Checking GCP project access... "
PROJECT_COUNT=$(gcloud projects list 2>/dev/null | grep -v "PROJECT_ID" | wc -l | tr -d ' ')
if [[ $PROJECT_COUNT -gt 0 ]]; then
    echo -e "${GREEN}✓ Access granted${NC} ($PROJECT_COUNT projects)"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗ NO PROJECTS ACCESSIBLE${NC}"
    echo "  Verify permissions with your GCP administrator"
    ((CHECKS_FAILED++))
fi

# Check 4: Default project configured
echo -n "Checking default project... "
DEFAULT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ -n "$DEFAULT_PROJECT" ]]; then
    echo -e "${GREEN}✓ Set${NC} to $DEFAULT_PROJECT"
    ((CHECKS_PASSED++))
else
    echo -e "${YELLOW}⚠ Not set${NC}"
    echo "  Optional: gcloud config set project PROJECT_ID"
fi

# Check 5: Compute Engine API enabled (on default project if set)
if [[ -n "$DEFAULT_PROJECT" ]]; then
    echo -n "Checking Compute Engine API... "
    if gcloud services list --enabled --project="$DEFAULT_PROJECT" 2>/dev/null | grep -q compute.googleapis.com; then
        echo -e "${GREEN}✓ Enabled${NC}"
        ((CHECKS_PASSED++))
    else
        echo -e "${YELLOW}⚠ Not enabled${NC}"
        echo "  Enable: gcloud services enable compute.googleapis.com --project=$DEFAULT_PROJECT"
    fi
fi

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical checks passed${NC}"
    echo -e "  Ready to provision developer VMs"
    exit 0
else
    echo -e "${RED}✗ $CHECKS_FAILED check(s) failed${NC}"
    echo -e "  Fix issues above before continuing"
    exit 1
fi
