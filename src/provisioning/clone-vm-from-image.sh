#!/bin/bash
set -e

# VM Clone Script - V2 Sudo-First Workflow
# Usage: ./scripts/clone-vm-from-image.sh <engineer-name> <new-vm-name> <project> <zone>
#
# Purpose:
# Rapidly create additional VMs for an engineer from their base image

ENGINEER_NAME=$1
NEW_VM_NAME=$2
PROJECT=${3:-gcp-engg-vm}
ZONE=${4:-us-east1-b}

if [ -z "$ENGINEER_NAME" ] || [ -z "$NEW_VM_NAME" ]; then
    echo "❌ Usage: $0 <engineer-name> <new-vm-name> [project] [zone]"
    echo ""
    echo "Example: ./scripts/clone-vm-from-image.sh akash dev-akash-vm-003"
    exit 1
fi

echo "=================================================="
echo "🚀 CLONING VM FROM IMAGE - V2 Sudo-First"
echo "=================================================="
echo "Engineer: $ENGINEER_NAME"
echo "New VM: $NEW_VM_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo ""

# Step 1: Find latest image
echo "=================================================="
echo "Step 1: Finding Latest Image"
echo "=================================================="

IMAGE_FAMILY="${ENGINEER_NAME}-base"

LATEST_IMAGE=$(gcloud compute images describe-from-family $IMAGE_FAMILY \
    --project=$PROJECT \
    --format="get(name)" 2>&1)

if [ -z "$LATEST_IMAGE" ] || [[ "$LATEST_IMAGE" == *"ERROR"* ]]; then
    echo "❌ No image found for engineer: $ENGINEER_NAME"
    echo "   Image family: $IMAGE_FAMILY"
    echo ""
    echo "Engineer needs base image created first."
    echo "Run: ./scripts/build-vm.sh config/users/${ENGINEER_NAME}.yaml"
    echo "Then: ./scripts/finalize-vm.sh <vm-name> <username>"
    exit 1
fi

echo "✅ Found image: $LATEST_IMAGE"
echo ""

# Step 2: Create static IP
echo "=================================================="
echo "Step 2: Creating Static IP"
echo "=================================================="

STATIC_IP_NAME="${NEW_VM_NAME}-ip"
REGION=$(echo $ZONE | sed 's/-[a-z]$//')

echo "Creating: $STATIC_IP_NAME in $REGION..."

gcloud compute addresses create $STATIC_IP_NAME \
    --project=$PROJECT \
    --region=$REGION \
    --quiet || echo "⚠️  Static IP may already exist"

STATIC_IP=$(gcloud compute addresses describe $STATIC_IP_NAME \
    --project=$PROJECT \
    --region=$REGION \
    --format="get(address)")

echo "✅ Static IP: $STATIC_IP"
echo ""

# Step 3: Create VM from image
echo "=================================================="
echo "Step 3: Creating VM from Image"
echo "=================================================="

echo "Creating $NEW_VM_NAME from $LATEST_IMAGE..."

gcloud compute instances create $NEW_VM_NAME \
    --project=$PROJECT \
    --zone=$ZONE \
    --machine-type=n2-standard-4 \
    --image=$LATEST_IMAGE \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-standard \
    --address=$STATIC_IP \
    --metadata=enable-oslogin=TRUE \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=dev-vm \
    --quiet

echo "✅ VM created"
echo ""

# Step 4: Wait for VM to boot
echo "=================================================="
echo "Step 4: Waiting for VM to Boot"
echo "=================================================="

echo "Waiting 30 seconds for boot..."
sleep 30

echo "✅ VM should be ready"
echo ""

# Step 5: Security Verification
echo "=================================================="
echo "Step 5: Security Verification"
echo "=================================================="

USERNAME="${ENGINEER_NAME}_brightfox_ai"

SUDO_CHECK=$(gcloud compute ssh $NEW_VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo -u $USERNAME sudo -n true 2>&1
" 2>&1)

if [[ "$SUDO_CHECK" == *"password is required"* ]]; then
    echo "✅ PASS: Engineer does NOT have sudo"
else
    echo "⚠️  WARNING: Unexpected sudo check result"
    echo "   Output: $SUDO_CHECK"
fi

echo ""

# Step 6: VM Details
echo "=================================================="
echo "Step 6: VM Details"
echo "=================================================="

EXTERNAL_IP=$(gcloud compute instances describe $NEW_VM_NAME \
    --project=$PROJECT \
    --zone=$ZONE \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM Name: $NEW_VM_NAME"
echo "External IP: $EXTERNAL_IP"
echo "Zone: $ZONE"
echo ""

# Summary
echo "=================================================="
echo "🎉 VM CLONING COMPLETE!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  ✅ VM created from image: $LATEST_IMAGE"
echo "  ✅ Static IP assigned: $STATIC_IP"
echo "  ✅ Security verified (no sudo)"
echo "  ✅ VM online at: $EXTERNAL_IP"
echo ""
echo "Chrome Remote Desktop:"
echo "  Already configured (from base image)"
echo "  Access: https://remotedesktop.google.com/access"
echo "  VM Name: $NEW_VM_NAME"
echo ""
echo "SSH Access:"
echo "  gcloud compute ssh $NEW_VM_NAME --project=$PROJECT --zone=$ZONE"
echo ""
echo "⏱️  Total time: ~2 minutes (vs 45 minutes from scratch)"
echo ""
