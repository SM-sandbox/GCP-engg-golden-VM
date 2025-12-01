#!/bin/bash
set -e

# NoMachine Firewall Configuration Script
# Creates GCP firewall rule and tags VM for NoMachine access
# Usage: ./setup-nomachine-firewall.sh <vm-name> [project] [zone]

VM_NAME="$1"
PROJECT="${2:-gcp-engg-vm}"
ZONE="${3:-us-east1-b}"

if [ -z "$VM_NAME" ]; then
    echo "❌ Usage: $0 <vm-name> [project] [zone]"
    echo "   Example: $0 dev-akash-vm-002"
    exit 1
fi

echo "=================================================="
echo "🔥 Configuring NoMachine Firewall"
echo "=================================================="
echo "VM: $VM_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo ""

# Step 1: Create firewall rule (idempotent - won't fail if exists)
echo "➡️  Creating firewall rule 'allow-nomachine'..."
gcloud compute firewall-rules create allow-nomachine \
    --project="$PROJECT" \
    --network=default \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:4000,tcp:4011-4020 \
    --target-tags=nomachine-enabled \
    --description="Allow NoMachine remote desktop access (ports 4000, 4011-4020)" \
    --quiet 2>/dev/null && echo "✅ Firewall rule created" || echo "✅ Firewall rule already exists"

echo ""

# Step 2: Tag the VM
echo "➡️  Adding 'nomachine-enabled' tag to VM..."
gcloud compute instances add-tags "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --tags=nomachine-enabled

echo "✅ VM tagged successfully"
echo ""

# Step 3: Verify configuration
echo "➡️  Verifying configuration..."
VM_TAGS=$(gcloud compute instances describe "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --format="value(tags.items)")

if [[ "$VM_TAGS" == *"nomachine-enabled"* ]]; then
    echo "✅ Tag verified: nomachine-enabled"
else
    echo "⚠️  Warning: Tag may not be applied correctly"
fi

VM_IP=$(gcloud compute instances describe "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "=================================================="
echo "✅ NoMachine Firewall Configuration Complete!"
echo "=================================================="
echo ""
echo "VM Details:"
echo "  - Name: $VM_NAME"
echo "  - External IP: $VM_IP"
echo "  - NoMachine Port: 4000"
echo "  - Connection String: $VM_IP:4000"
echo ""
echo "Firewall Rules Applied:"
echo "  - TCP Port 4000 (main NoMachine port)"
echo "  - TCP Ports 4011-4020 (auxiliary channels)"
echo ""
echo "Next Steps:"
echo "1. Ensure NoMachine is installed: ./install-nomachine.sh $VM_NAME"
echo "2. Engineer downloads NoMachine client: https://www.nomachine.com/download"
echo "3. Engineer connects to: $VM_IP:4000"
echo ""
