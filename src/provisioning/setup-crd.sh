#!/bin/bash
set -e

# Chrome Remote Desktop Onboarding Script
# Usage: ./scripts/setup-crd.sh <vm-name> <username> <auth-code> <project> <zone>
#
# Purpose:
# This script performs the "Sudo Dance" required to register a new Chrome Remote Desktop host.
# The engineer does NOT have sudo access, but CRD registration requires root.
# This script (run by the ADMIN) temporarily impersonates the user with elevated privileges
# to run the registration command, then ensures sudo is revoked.

VM_NAME=$1
USERNAME=$2
AUTH_CODE=$3
PROJECT=${4:-gcp-engg-vm}
ZONE=${5:-us-east1-b}

if [ -z "$VM_NAME" ] || [ -z "$USERNAME" ] || [ -z "$AUTH_CODE" ]; then
    echo "❌ Usage: $0 <vm-name> <username> <auth-code> [project] [zone]"
    exit 1
fi

echo "=================================================="
echo "🔐 Chrome Remote Desktop Onboarding"
echo "=================================================="
echo "VM: $VM_NAME"
echo "User: $USERNAME"
echo "Project: $PROJECT"
echo ""

# 1. Verify native IAM roles (sanity check)
echo "STEP 1: Verifying Native IAM Roles..."
# Convert OS Login username to email (e.g., ankush_brightfox_ai -> ankush@brightfox.ai)
EMAIL_PREFIX=$(echo "$USERNAME" | sed 's/_brightfox_ai$//')
USER_EMAIL="${EMAIL_PREFIX}@brightfox.ai"

ROLES=$(gcloud projects get-iam-policy $PROJECT --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:user:$USER_EMAIL")

if [[ "$ROLES" == *"roles/compute.instanceAdmin.v1"* ]]; then
    echo "❌ CRITICAL SECURITY RISK: User $USER_EMAIL has instanceAdmin.v1 role!"
    echo "   This role grants implicit sudo access via OS Login."
    echo "   Please remove this role and grant 'CustomEngineerRole' instead."
    exit 1
fi

echo "✅ IAM Roles look correct (no implicit sudo)."
echo ""

# 2. The Sudo Dance
echo "STEP 2: Registering Host (The Sudo Dance)..."
echo "   - Granting temporary sudo via 'google-sudoers'..."
echo "   - Running start-host command..."
echo "   - Revoking sudo immediately..."

# We use a single SSH command chain to minimize the window
# We use 'sudo -u' to run the CRD command as the engineer, but we need to give them sudo
# access temporarily because start-host internally calls sudo.

# The "Nuclear Option" command chain:
# 1. Add user to google-sudoers (Group Grant)
# 2. Run start-host command as the user
# 3. Remove user from google-sudoers (Group Revoke)

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --tunnel-through-iap --command="
    echo '   >>> [REMOTE] Granting Sudo...'
    sudo usermod -aG google-sudoers ${USERNAME}
    
    echo '   >>> [REMOTE] Disabling Lock Screen...'
    sudo -u ${USERNAME} dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled false
    sudo -u ${USERNAME} dbus-launch gsettings set org.gnome.desktop.session idle-delay 0

    echo '   >>> [REMOTE] Running Registration...'
    sudo -u ${USERNAME} bash -c \"DISPLAY= /opt/google/chrome-remote-desktop/start-host --code='$AUTH_CODE' --redirect-url='https://remotedesktop.google.com/_/oauthredirect' --name=\$(hostname) --pin='123456'\"
    
    echo '   >>> [REMOTE] Revoking Sudo...'
    sudo gpasswd -d ${USERNAME} google-sudoers
"

echo ""
echo "STEP 3: Verifying Sudo Revocation..."
# Verify they are definitely out
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --tunnel-through-iap --command="
    if groups ${USERNAME} | grep -q 'google-sudoers'; then
        echo '❌ FAIL: User is still in google-sudoers group!'
        echo '   Fixing immediately...'
        sudo gpasswd -d ${USERNAME} google-sudoers
    else
        echo '✅ SUCCESS: User is NOT in google-sudoers.'
    fi
"

echo ""
echo "=================================================="
echo "🎉 Onboarding Complete!"
echo "=================================================="
echo "The engineer can now connect via https://remotedesktop.google.com/"
