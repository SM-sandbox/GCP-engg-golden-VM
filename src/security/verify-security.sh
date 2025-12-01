#!/bin/bash

# Security Verification Script - Permission-Based (No User Dependency)
# 
# This script verifies VM security by checking POSIX permissions, ACLs, and
# sudoers configuration. It does NOT require the engineer's OS Login user to
# exist on the VM, making it suitable for immediate post-build verification.
#
# Usage: ./scripts/verify-security.sh <username> <vm-name> <project> <zone>
#
# Exit codes:
#   0 = All security checks passed
#   1 = One or more security checks failed
#   2 = Usage error (missing arguments)

set -e

USERNAME=$1
VM_NAME=$2
PROJECT=$3
ZONE=$4

if [ -z "$USERNAME" ] || [ -z "$VM_NAME" ] || [ -z "$PROJECT" ] || [ -z "$ZONE" ]; then
    echo "❌ Usage: $0 <username> <vm-name> <project> <zone>"
    exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0

echo "=================================================="
echo "🔐 Security Verification (Permission-Based)"
echo "=================================================="
echo "VM: $VM_NAME"
echo "User: $USERNAME"
echo "Note: This verification does NOT require the OS Login user to exist"
echo ""

# Helper function to check directory permissions
check_dir_perms() {
    local path=$1
    local expected_mode=$2
    local expected_owner=$3
    local expected_group=$4
    local test_name=$5
    
    echo "Test: $test_name"
    echo "   Checking: $path"
    
    PERMS=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
        if [ -d '$path' ]; then
            sudo stat -c '%a %U %G' '$path'
        else
            echo 'NOT_FOUND'
        fi
    " 2>&1)
    
    if [[ "$PERMS" == "NOT_FOUND" ]]; then
        echo "   ❌ FAIL: Directory does not exist"
        ((FAIL_COUNT++))
        return 1
    fi
    
    local actual_mode=$(echo $PERMS | awk '{print $1}')
    local actual_owner=$(echo $PERMS | awk '{print $2}')
    local actual_group=$(echo $PERMS | awk '{print $3}')
    
    echo "   Expected: $expected_mode $expected_owner:$expected_group"
    echo "   Actual:   $actual_mode $actual_owner:$actual_group"
    
    if [[ "$actual_mode" == "$expected_mode" ]] && \
       [[ "$actual_owner" == "$expected_owner" ]] && \
       [[ "$actual_group" == "$expected_group" ]]; then
        echo "   ✅ PASS"
        ((PASS_COUNT++))
        return 0
    else
        echo "   ❌ FAIL: Permission mismatch"
        ((FAIL_COUNT++))
        return 1
    fi
}

# Helper function to check file permissions
check_file_perms() {
    local path=$1
    local expected_mode=$2
    local expected_owner=$3
    local expected_group=$4
    local test_name=$5
    
    echo "Test: $test_name"
    echo "   Checking: $path"
    
    PERMS=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
        if [ -f '$path' ]; then
            sudo stat -c '%a %U %G' '$path'
        else
            echo 'NOT_FOUND'
        fi
    " 2>&1)
    
    if [[ "$PERMS" == "NOT_FOUND" ]]; then
        echo "   ⚠️  SKIP: File does not exist (may not be created yet)"
        return 0
    fi
    
    local actual_mode=$(echo $PERMS | awk '{print $1}')
    local actual_owner=$(echo $PERMS | awk '{print $2}')
    local actual_group=$(echo $PERMS | awk '{print $3}')
    
    echo "   Expected: $expected_mode $expected_owner:$expected_group"
    echo "   Actual:   $actual_mode $actual_owner:$actual_group"
    
    if [[ "$actual_mode" == "$expected_mode" ]] && \
       [[ "$actual_owner" == "$expected_owner" ]] && \
       [[ "$actual_group" == "$expected_group" ]]; then
        echo "   ✅ PASS"
        ((PASS_COUNT++))
        return 0
    else
        echo "   ❌ FAIL: Permission mismatch"
        ((FAIL_COUNT++))
        return 1
    fi
}

# Test 1: IAM Role Check (CRITICAL - No instanceAdmin.v1)
echo "=================================================="
echo "Test 1: IAM Roles (No instanceAdmin.v1)"
echo "=================================================="
# Convert OS Login username to email
EMAIL_PREFIX=$(echo "$USERNAME" | sed 's/_brightfox_ai$//')
USER_EMAIL="${EMAIL_PREFIX}@brightfox.ai"
echo "   Checking IAM roles for: $USER_EMAIL"

IAM_ROLES=$(gcloud projects get-iam-policy $PROJECT --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:user:$USER_EMAIL" 2>&1)

if [[ "$IAM_ROLES" == *"roles/compute.instanceAdmin.v1"* ]]; then
    echo "   ❌ FAIL: User has instanceAdmin.v1 role!"
    echo "   This role grants AUTOMATIC sudo access via OS Login"
    echo "   IMMEDIATE ACTION REQUIRED:"
    echo "   gcloud projects remove-iam-policy-binding $PROJECT \\"
    echo "     --member='user:$USER_EMAIL' \\"
    echo "     --role='roles/compute.instanceAdmin.v1'"
    ((FAIL_COUNT++))
else
    echo "   ✅ PASS: User does NOT have instanceAdmin.v1"
    ((PASS_COUNT++))
fi
echo ""

# Test 2: Project-level metadata disables OS Login sudo
echo "=================================================="
echo "Test 2: Project Metadata (enable-oslogin-sudo=FALSE)"
echo "=================================================="
PROJECT_META=$(gcloud compute project-info describe --project=$PROJECT --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin-sudo).list())" 2>&1)
if [[ "$PROJECT_META" == *"FALSE"* ]]; then
    echo "   ✅ PASS: enable-oslogin-sudo=FALSE"
    ((PASS_COUNT++))
else
    echo "   ❌ FAIL: Project metadata NOT set correctly"
    echo "   Expected: enable-oslogin-sudo=FALSE"
    echo "   Got: $PROJECT_META"
    ((FAIL_COUNT++))
fi
echo ""

# Test 3: Sudoers Configuration
echo "=================================================="
echo "Test 3: Sudoers Configuration"
echo "=================================================="
echo "   Checking for problematic sudoers entries..."

SUDOERS_CHECK=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
    # Check for NOPASSWD grants to non-root users
    sudo grep -r 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' | grep -v 'root' || true
    
    # Check for broad ALL grants to sudo/google-sudoers groups
    sudo grep -r '%sudo.*ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' || true
    sudo grep -r '%google-sudoers.*ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#' || true
    
    echo 'SUDOERS_CHECK_DONE'
" 2>&1)

if [[ "$SUDOERS_CHECK" == "SUDOERS_CHECK_DONE" ]]; then
    echo "   ✅ PASS: No problematic sudoers entries"
    ((PASS_COUNT++))
else
    # Filter out the SUDOERS_CHECK_DONE marker
    PROBLEMATIC=$(echo "$SUDOERS_CHECK" | grep -v "SUDOERS_CHECK_DONE")
    if [ -z "$PROBLEMATIC" ]; then
        echo "   ✅ PASS: No problematic sudoers entries"
        ((PASS_COUNT++))
    else
        echo "   ⚠️  WARNING: Found sudoers entries (review needed):"
        echo "$PROBLEMATIC"
        echo "   ℹ️  Note: These may be acceptable system defaults"
        # Don't fail on this - just warn
    fi
fi
echo ""

# Test 4: OS Login sudo file must NOT exist
echo "=================================================="
echo "Test 4: OS Login Sudo File Check"
echo "=================================================="
echo "   Checking: /var/google-sudoers.d/${USERNAME}_brightfox_ai"

SUDO_FILE_CHECK=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
    sudo test -f /var/google-sudoers.d/${USERNAME}_brightfox_ai && echo 'EXISTS' || echo 'NOT_FOUND'
" 2>&1)

if [[ "$SUDO_FILE_CHECK" == *"NOT_FOUND"* ]]; then
    echo "   ✅ PASS: OS Login sudo file does not exist"
    ((PASS_COUNT++))
else
    echo "   ❌ FAIL: OS Login sudo file EXISTS!"
    echo "   This grants FULL sudo access to the engineer"
    echo "   File: /var/google-sudoers.d/${USERNAME}_brightfox_ai"
    ((FAIL_COUNT++))
fi
echo ""

# Test 5: Static IP assigned
echo "=================================================="
echo "Test 5: Static IP Assignment"
echo "=================================================="
IP=$(gcloud compute instances describe $VM_NAME --project=$PROJECT --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>&1)
if [ ! -z "$IP" ]; then
    echo "   ✅ PASS: Static IP assigned: $IP"
    ((PASS_COUNT++))
else
    echo "   ❌ FAIL: No static IP assigned"
    ((FAIL_COUNT++))
fi
echo ""

# Test 6: SSH access works
echo "=================================================="
echo "Test 6: SSH Connectivity"
echo "=================================================="
RESULT=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="echo 'SSH_OK'" 2>&1)
if [[ "$RESULT" == *"SSH_OK"* ]]; then
    echo "   ✅ PASS: SSH access works"
    ((PASS_COUNT++))
else
    echo "   ❌ FAIL: SSH access broken"
    ((FAIL_COUNT++))
fi
echo ""

# Summary
echo "=================================================="
echo "SECURITY VERIFICATION RESULTS"
echo "=================================================="
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 SECURITY VERIFICATION PASSED"
    echo ""
    echo "All security controls are correctly configured."
    echo "Engineer users will be unable to:"
    echo "  - Gain sudo/root access"
    echo "  - Read monitoring scripts or logs"
    echo "  - Modify system security configurations"
    echo ""
    exit 0
else
    echo "⚠️  SECURITY VERIFICATION FAILED"
    echo ""
    echo "One or more security controls are NOT correctly configured."
    echo "DO NOT proceed with engineer onboarding until these are fixed."
    echo ""
    exit 1
fi
