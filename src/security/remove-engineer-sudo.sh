#!/bin/bash
# Remove sudo access for engineers
# This script ensures engineers NEVER have sudo access via OS Login

set -e

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <username> <vm-name> <project> <zone>"
    echo "Example: $0 akash dev-akash-vm-001 gcp-engg-vm us-east1-b"
    exit 1
fi

USERNAME=$1
VM_NAME=$2
PROJECT=$3
ZONE=$4

echo "🔒 Removing sudo access for ${USERNAME}..."

gcloud compute ssh ${VM_NAME} --project=${PROJECT} --zone=${ZONE} --command="
# Remove user from all sudo groups
sudo gpasswd -d ${USERNAME} google-sudoers 2>/dev/null || true
sudo gpasswd -d ${USERNAME} sudo 2>/dev/null || true
sudo gpasswd -d ${USERNAME} adm 2>/dev/null || true

# Remove OS Login sudo file
sudo rm -f /var/google-sudoers.d/${USERNAME}_brightfox_ai

# Verify removal
if [ -f /var/google-sudoers.d/${USERNAME}_brightfox_ai ]; then
    echo '❌ FAILED: Sudo file still exists!'
    exit 1
else
    echo '✅ Sudo file removed'
fi

# List remaining sudo users
echo ''
echo 'Remaining sudo users in /var/google-sudoers.d/:'
sudo ls -1 /var/google-sudoers.d/
"

echo ""
echo "✅ Sudo access removed for ${USERNAME}"
