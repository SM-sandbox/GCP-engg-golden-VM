#!/bin/bash
# VM Build Script - Fully Automated
# Usage: ./scripts/build-vm.sh config/users/username.yaml

CONFIG_FILE="$1"

if [ -z "$CONFIG_FILE" ]; then
    echo "❌ Usage: $0 <config-file>"
    exit 1
fi

# Build Metadata
BUILD_VERSION="1.0"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUILD_DIR="builds"
mkdir -p "$BUILD_DIR"

# Parse VM Name early for log naming
VM_NAME=$(grep "^  name:" "$CONFIG_FILE" | awk '{print $2}')
if [ -z "$VM_NAME" ]; then
    VM_NAME="unknown-vm"
fi

# Artifacts
LOG_FILE="$BUILD_DIR/build-${VM_NAME}-${TIMESTAMP}-v${BUILD_VERSION}.log"
CONFIG_COPY="$BUILD_DIR/build-${VM_NAME}-${TIMESTAMP}-v${BUILD_VERSION}.yaml"

# Save Build Artifacts
cp "$CONFIG_FILE" "$CONFIG_COPY"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "🚀 VM BUILD SYSTEM v${BUILD_VERSION}"
echo "=================================================="
echo "📝 Logging to: $LOG_FILE"
echo "💾 Config saved: $CONFIG_COPY"

SECONDS=0
STEP_START=$SECONDS

function finish_step() {
    STEP_NAME=$1
    DURATION=$((SECONDS - STEP_START))
    echo "⏱️  Step '$STEP_NAME' completed in ${DURATION}s."
    STEP_START=$SECONDS
}

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "=================================================="
echo "🚀 VM BUILD SYSTEM - Automated Provisioning"
echo "=================================================="
echo ""
echo "📄 Config: $CONFIG_FILE"
echo ""

# Parse YAML (simple grep-based parsing)
USER_EMAIL=$(grep "^  email:" "$CONFIG_FILE" | awk '{print $2}')
USERNAME=$(grep "^  username:" "$CONFIG_FILE" | awk '{print $2}')
VM_NAME=$(grep "^  name:" "$CONFIG_FILE" | awk '{print $2}')
PROJECT=$(grep "^  project:" "$CONFIG_FILE" | awk '{print $2}')
IMAGE=$(grep "^  image:" "$CONFIG_FILE" | awk '{print $2}')
IMAGE_FAMILY=$(grep "^  image_family:" "$CONFIG_FILE" | awk '{print $2}')
IMAGE_PROJECT=$(grep "^  image_project:" "$CONFIG_FILE" | awk '{print $2}')

if [ ! -z "$IMAGE" ]; then
    echo "Using specific image: $IMAGE"
    IMAGE_FLAG="--image=$IMAGE"
else
    echo "Using image family: $IMAGE_FAMILY"
    IMAGE_FLAG="--image-family=$IMAGE_FAMILY"
fi
ZONE=$(grep "^  zone:" "$CONFIG_FILE" | awk '{print $2}')
MACHINE_TYPE=$(grep "^  machine_type:" "$CONFIG_FILE" | awk '{print $2}')
DISK_SIZE=$(grep "^  disk_size_gb:" "$CONFIG_FILE" | awk '{print $2}')

STATIC_IP_NAME="${VM_NAME}-ip"
REGION=$(echo $ZONE | sed 's/-[a-z]$//')

echo "👤 User: $USERNAME ($USER_EMAIL)"
echo "🖥️  VM: $VM_NAME"
echo "📍 Project: $PROJECT"
echo "🌍 Zone: $ZONE"
echo ""

# Pre-flight check: Verify project-level security metadata
echo "=================================================="
echo "Pre-Flight: Verifying Project Security Settings"
echo "=================================================="

PROJECT_SUDO_META=$(gcloud compute project-info describe --project=$PROJECT --format="value(commonInstanceMetadata.items.filter(key:enable-oslogin-sudo).list())" 2>&1 || echo "NOT_SET")

if [[ "$PROJECT_SUDO_META" == *"FALSE"* ]]; then
    echo "✅ Project metadata: enable-oslogin-sudo=FALSE (Correct)"
else
    echo "❌ CRITICAL: Project metadata enable-oslogin-sudo is NOT set to FALSE!"
    echo "   Current value: $PROJECT_SUDO_META"
    echo ""
    echo "   This MUST be set before building VMs. Run:"
    echo "   gcloud compute project-info add-metadata --project=$PROJECT --metadata=enable-oslogin-sudo=FALSE"
    echo ""
    exit 1
fi

echo ""

# Step 1: Ensure IAP Firewall Rule Exists
echo "=================================================="
echo "Step 1: Verifying IAP Firewall Rule"
echo "=================================================="
echo "Ensuring IAP firewall rule exists for SSH access..."

gcloud compute firewall-rules create allow-ssh-from-iap \
    --project=$PROJECT \
    --network=default \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=dev-vm \
    --description="Allow SSH via IAP for Identity-Aware Proxy" \
    --quiet 2>/dev/null || echo "✅ IAP firewall rule already exists"

echo "✅ IAP firewall rule verified"
finish_step "IAP Firewall"
echo ""

# Step 2: Create static IP
echo "=================================================="
echo "Step 2: Creating Static IP"
echo "=================================================="
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
finish_step "Static IP"
echo ""

# Step 3: Create VM
echo "=================================================="
echo "Step 3: Creating VM"
echo "=================================================="
echo "Creating $VM_NAME..."

gcloud compute instances create $VM_NAME \
    --project=$PROJECT \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --image-project=$IMAGE_PROJECT \
    $IMAGE_FLAG \
    --boot-disk-size=${DISK_SIZE}GB \
    --boot-disk-type=pd-balanced \
    --address=$STATIC_IP \
    --metadata=enable-oslogin=TRUE \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=dev-vm \
    --quiet
# Note: enable-oslogin-sudo=FALSE is set at PROJECT level, not instance level

echo "✅ VM created: $VM_NAME"
echo "⏳ Waiting for VM to boot (30 seconds)..."
sleep 30
finish_step "VM Creation"
echo ""

# Step 4: Grant IAM Permissions
echo "=================================================="
echo "Step 4: Granting IAM Permissions"
echo "=================================================="

# Permission 1: Custom Engineer Role (Start/Stop/Reset/Get/List)
echo "Creating/Verifying Custom Engineer Role..."
gcloud iam roles create CustomEngineerRole --project=$PROJECT \
    --title="Custom Engineer Role" \
    --description="Can start/stop VMs but no sudo access" \
    --permissions=compute.instances.start,compute.instances.stop,compute.instances.reset,compute.instances.get,compute.instances.list,compute.projects.get \
    --quiet 2>/dev/null || echo "✅ Role CustomEngineerRole already exists"

echo "Granting CustomEngineerRole..."
gcloud projects add-iam-policy-binding $PROJECT \
    --member="user:$USER_EMAIL" \
    --role="projects/$PROJECT/roles/CustomEngineerRole" \
    --condition=None \
    --quiet > /dev/null

# Permission 2: compute.osLogin
echo "Granting compute.osLogin..."
gcloud projects add-iam-policy-binding $PROJECT \
    --member="user:$USER_EMAIL" \
    --role="roles/compute.osLogin" \
    --condition=None \
    --quiet > /dev/null

# Permission 3: compute.instanceAdmin.v1 (TEMPORARY - For CRD Self-Setup)
echo "⚠️  Granting TEMPORARY compute.instanceAdmin.v1 for CRD setup..."
gcloud projects add-iam-policy-binding $PROJECT \
    --member="user:$USER_EMAIL" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None \
    --quiet > /dev/null

# Permission 4: iam.serviceAccountUser
echo "Granting iam.serviceAccountUser..."
SERVICE_ACCOUNT=$(gcloud compute instances describe $VM_NAME \
    --project=$PROJECT \
    --zone=$ZONE \
    --format="get(serviceAccounts[0].email)")

gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT \
    --project=$PROJECT \
    --member="user:$USER_EMAIL" \
    --role="roles/iam.serviceAccountUser" \
    --quiet > /dev/null

# Permission 5: iap.tunnelResourceAccessor (Required for IAP TCP forwarding)
echo "Granting iap.tunnelResourceAccessor..."
gcloud projects add-iam-policy-binding $PROJECT \
    --member="user:$USER_EMAIL" \
    --role="roles/iap.tunnelResourceAccessor" \
    --condition=None \
    --quiet > /dev/null

echo "✅ All 5 IAM permissions granted"
finish_step "IAM Config"
echo ""

# Step 5: Install Chrome Remote Desktop
echo "=================================================="
echo "Step 5: Installing Chrome Remote Desktop"
echo "=================================================="

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
# Update system
sudo apt-get update -qq

# Install Xfce desktop environment (lightweight, modern, no GPU required)
echo 'Installing Xfce Desktop (takes 3-5 minutes)...'
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 xfce4-goodies xfce4-terminal -qq

# CRITICAL: Install dbus-x11 (required for CRD desktop sessions)
echo 'Installing dbus-x11 for Chrome Remote Desktop...'
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dbus-x11 -qq

# Disable GNOME Lock Screen (Moved to setup-crd.sh because user might not exist yet)
# echo \"Disabling GNOME Lock Screen...\"
# sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled false
# sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.session idle-delay 0

# Download and install CRD
wget -q https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ./chrome-remote-desktop_current_amd64.deb -qq
rm chrome-remote-desktop_current_amd64.deb

echo '🖥️ **CHROME REMOTE DESKTOP - SELF-SETUP INSTRUCTIONS:**'
echo ''
echo 'YOU NOW HAVE SUDO ACCESS to complete CRD setup yourself.'
echo ''
echo 'Follow these steps:'
echo '1. Visit https://remotedesktop.google.com/headless'
echo '2. Click Begin, Next, Authorize with your BrightFox email'
echo '3. Copy the full command (starts with DISPLAY=...)'
echo '4. SSH to this VM and run that command'
echo '5. Set a PIN when prompted'
echo '6. Run: ~/disable-lockscreen.sh (prevents login prompts)'
echo '7. Notify Scott when complete'
echo ''
echo 'SSH command: gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE'
echo ''
echo '⚠️  IMPORTANT: Your sudo access is TEMPORARY.'
echo 'After CRD setup, Scott will finalize the VM and remove sudo.'
echo ''
echo '✅ Chrome Remote Desktop installed - awaiting your setup'
" || { echo "❌ CRD installation failed"; exit 1; }

# Create setup phase flag and upload helper script
echo "Creating setup phase flag and helper scripts..."
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo touch /tmp/engineer-setup-phase
sudo chmod 644 /tmp/engineer-setup-phase
"

# Upload lockscreen disable script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gcloud compute scp "$SCRIPT_DIR/disable-lockscreen.sh" $VM_NAME:/tmp/disable-lockscreen.sh --project=$PROJECT --zone=$ZONE --quiet
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo mv /tmp/disable-lockscreen.sh /home/ubuntu/disable-lockscreen.sh
sudo chmod +x /home/ubuntu/disable-lockscreen.sh
"

echo "✅ CRD installed - engineer will self-setup"
finish_step "CRD Setup"
echo ""

# Step 6: Install User Applications (Chrome, Windsurf, Jupyter)
echo "=================================================="
echo "Step 6: Installing Applications"
echo "=================================================="

# Parse application config (simple grep)
# Default to installing ALL if 'applications' section is missing (backward compatibility)
if grep -q "^applications:" "$CONFIG_FILE"; then
    APP_CHROME=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "chrome:" | awk '{print $2}')
    APP_WINDSURF=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "windsurf:" | awk '{print $2}')
    APP_JUPYTER=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "jupyter:" | awk '{print $2}')
    APP_PYTHON=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "python:" | awk '{print $2}')
    APP_NODE=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "node:" | awk '{print $2}')
    APP_GIT=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "git:" | awk '{print $2}')
    APP_UTILS=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "utils:" | awk '{print $2}')
    APP_BUILD_TOOLS=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "build_tools:" | awk '{print $2}')
    APP_GITHUB_CLI=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "github_cli:" | awk '{print $2}')
    APP_AZURE_CLI=$(grep -A 15 "^applications:" "$CONFIG_FILE" | grep "azure_cli:" | awk '{print $2}')
else
    echo "ℹ️  'applications' section missing in config - Installing ALL by default"
    APP_CHROME="true"
    APP_WINDSURF="true"
    APP_JUPYTER="true"
    APP_PYTHON="true"
    APP_NODE="true"
    APP_GIT="true"
    APP_UTILS="true"
    APP_BUILD_TOOLS="true"
    APP_GITHUB_CLI="true"
    APP_AZURE_CLI="true"
fi

# Construct flags
INSTALL_FLAGS=""
[ "$APP_CHROME" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --chrome"
[ "$APP_WINDSURF" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --windsurf"
[ "$APP_JUPYTER" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --jupyter"
[ "$APP_PYTHON" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --python"
[ "$APP_NODE" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --node"
[ "$APP_GIT" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --git"
[ "$APP_UTILS" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --utils"
[ "$APP_BUILD_TOOLS" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --build-tools"
[ "$APP_GITHUB_CLI" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --github-cli"
[ "$APP_AZURE_CLI" = "true" ] && INSTALL_FLAGS="$INSTALL_FLAGS --azure-cli"

echo "   Installing:$INSTALL_FLAGS"

gcloud compute scp ./scripts/install-apps.sh $VM_NAME:/tmp/ --project=$PROJECT --zone=$ZONE --quiet
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
    chmod +x /tmp/install-apps.sh
    sudo /tmp/install-apps.sh $INSTALL_FLAGS
" || echo "  App installation had issues"
finish_step "App Install"
echo ""

# Step 7: Verify NO sudo access
echo "=================================================="
echo "Step 7: Verifying NO Sudo Access"
echo "=================================================="

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
# Verify user is NOT in sudo groups (belt and braces)
sudo gpasswd -d $USERNAME google-sudoers 2>/dev/null || true
sudo gpasswd -d $USERNAME sudo 2>/dev/null || true
sudo gpasswd -d $USERNAME adm 2>/dev/null || true

# CRITICAL: Verify OS Login sudo file does NOT exist
# Due to enable-oslogin-sudo=FALSE metadata, this file should NEVER be created
if [ -f /var/google-sudoers.d/${USERNAME}_brightfox_ai ]; then
    echo '❌ CRITICAL FAILURE: OS Login sudo file exists despite metadata setting!'
    echo 'This should NEVER happen. Check enable-oslogin-sudo=FALSE is set.'
    exit 1
fi

echo '✅ Verified: No sudo groups'
echo '✅ Verified: No OS Login sudo file'
echo '✅ Engineer will have NO sudo access'
"
finish_step "Sudo Removal"
echo ""

# Step 8: Run security verification
echo "=================================================="
echo "Step 8: Security Verification"
echo "=================================================="
echo "NOTE: Verification is permission-based and does NOT require"
echo "      the engineer's OS Login user to exist yet."
echo ""

./scripts/verify-security.sh $USERNAME $VM_NAME $PROJECT $ZONE
finish_step "Security Audit"

echo ""

# Step 9: Install Productivity Monitoring (Activity, Git Stats, Backups)
echo "=================================================="
echo "Step 9: Installing Productivity Monitoring"
echo "=================================================="
# This script runs locally and uses gcloud to deploy to the VM
./vm-scripts/install_monitoring.sh "$CONFIG_FILE"
finish_step "Monitoring Install"

echo ""
echo "=================================================="
echo "✅ VM BUILD COMPLETE"
echo "=================================================="
echo ""
echo "📋 VM Details:"
echo "   Name: $VM_NAME"
echo "   IP: $STATIC_IP"
echo "   User: $USERNAME ($USER_EMAIL)"
echo "   Project: $PROJECT"
echo "   Zone: $ZONE"
echo ""
echo "📧 Generating onboarding email..."
echo ""

# Generate onboarding email
./scripts/generate-onboarding-email.sh "$CONFIG_FILE" "$STATIC_IP"

echo ""
echo "🎉 DONE! VM is ready for engineer."
echo ""
