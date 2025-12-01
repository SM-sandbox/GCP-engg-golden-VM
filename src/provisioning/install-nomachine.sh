#!/bin/bash
set -e

# NoMachine Server Installation Script
# Installs NoMachine server on an existing VM
# Usage: ./install-nomachine.sh <vm-name> [project] [zone]

VM_NAME="$1"
PROJECT="${2:-gcp-engg-vm}"
ZONE="${3:-us-east1-b}"

if [ -z "$VM_NAME" ]; then
    echo "❌ Usage: $0 <vm-name> [project] [zone]"
    echo "   Example: $0 dev-akash-vm-002"
    exit 1
fi

echo "=================================================="
echo "📦 Installing NoMachine Server"
echo "=================================================="
echo "VM: $VM_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo ""

echo "➡️  Connecting to VM and installing NoMachine..."
echo ""

gcloud compute ssh "$VM_NAME" --project="$PROJECT" --zone="$ZONE" --command="
set -e

echo '📥 Downloading NoMachine...'
cd /tmp

# Download from official NoMachine site (redirects to latest version)
wget https://www.nomachine.com/free/linux/64/deb -O nomachine.deb

# Verify download
if [ ! -f nomachine.deb ] || [ ! -s nomachine.deb ]; then
    echo '❌ Download failed or file is empty'
    exit 1
fi

echo '📦 Installing NoMachine package...'
sudo dpkg -i nomachine.deb || true
sudo apt-get install -f -y  # Fix any dependency issues

echo '🔧 Configuring NoMachine service...'
sudo systemctl enable nxserver
sudo systemctl start nxserver

echo '🧹 Cleaning up...'
rm -f nomachine.deb

echo ''
echo '✅ NoMachine server installed successfully!'
echo ''
echo 'NoMachine Status:'
sudo systemctl status nxserver --no-pager | head -10
"

echo ""
echo "=================================================="
echo "✅ NoMachine Installation Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Run ./setup-nomachine-firewall.sh $VM_NAME"
echo "2. Get VM IP: gcloud compute instances describe $VM_NAME --project=$PROJECT --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)'"
echo "3. Engineer downloads NoMachine client: https://www.nomachine.com/download"
echo "4. Engineer connects to VM_IP:4000"
echo ""
