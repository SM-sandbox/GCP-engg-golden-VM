#!/bin/bash
set -e

# VM Finalization Script - V2 Sudo-First Workflow
# Usage: ./scripts/finalize-vm.sh <vm-name> <username> <project> <zone>
#
# Purpose:
# After engineer completes CRD self-setup, this script:
# 1. Installs monitoring and tracking scripts
# 2. Secures monitoring directories (700 root:root)
# 3. Disables desktop lock screen (prevents CRD login prompts)
# 4. Removes temporary sudo access (revokes instanceAdmin.v1)
# 5. Deletes OS Login sudo files
# 6. Verifies final security posture (no sudo, monitoring secured)

VM_NAME=$1
USERNAME=$2
PROJECT=${3:-gcp-engg-vm}
ZONE=${4:-us-east1-b}

if [ -z "$VM_NAME" ] || [ -z "$USERNAME" ]; then
    echo "❌ Usage: $0 <vm-name> <username> [project] [zone]"
    exit 1
fi

# Convert username to email
EMAIL_PREFIX=$(echo "$USERNAME" | sed 's/_brightfox_ai$//')
USER_EMAIL="${EMAIL_PREFIX}@brightfox.ai"

echo "=================================================="
echo "🔒 VM FINALIZATION - V2 Sudo-First Workflow"
echo "=================================================="
echo "VM: $VM_NAME"
echo "User: $USERNAME"
echo "Email: $USER_EMAIL"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo ""

# Step 1: Verify engineer setup complete
echo "=================================================="
echo "Step 1: Verifying Engineer Setup Complete"
echo "=================================================="

SETUP_FLAG=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
test -f /tmp/engineer-setup-phase && echo 'EXISTS' || echo 'NOT_FOUND'
" 2>&1)

if [[ "$SETUP_FLAG" != *"EXISTS"* ]]; then
    echo "❌ ERROR: VM not in setup phase or flag missing"
    echo "   This VM may have already been finalized."
    exit 1
fi

echo "✅ Setup phase flag confirmed"
echo ""

# Step 2: Install monitoring scripts
echo "=================================================="
echo "Step 2: Installing Monitoring & Tracking"
echo "=================================================="

# Create temp package
TEMP_PKG=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Copying monitoring scripts to temp package..."
cp -r "$REPO_ROOT/vm-scripts"/* "$TEMP_PKG/"

# Create install wrapper
cat > "$TEMP_PKG/run-install.sh" << 'EOF'
#!/bin/bash
set -e

DEV_USER="$1"
PROJECTS_ROOT="/home/${DEV_USER}/projects"
ACTIVITY_LOG_DIR="/var/log/dev-activity"
GIT_LOG_DIR="/var/log/dev-git"
BACKUPS_DIR="/var/backups/dev-repos"
GCS_BUCKET="gcp-engg-vm-dev-logs"
INSTALL_DIR="/opt/dev-monitoring"

echo "Installing monitoring for user: $DEV_USER"

# Install dependencies
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-psutil xprintidle wmctrl scrot build-essential autotools-dev autoconf kbd git

# Create directories
sudo mkdir -p "$INSTALL_DIR"
sudo mkdir -p "$ACTIVITY_LOG_DIR"
sudo mkdir -p "$ACTIVITY_LOG_DIR/screenshots"
sudo mkdir -p "$ACTIVITY_LOG_DIR/keystrokes"
sudo mkdir -p "$GIT_LOG_DIR"
sudo mkdir -p "$BACKUPS_DIR"

# Copy scripts
sudo cp *.py *.sh "$INSTALL_DIR/" 2>/dev/null || true
sudo chmod 700 "$INSTALL_DIR"
sudo chmod -R 700 "$INSTALL_DIR"/*
sudo chown -R root:root "$INSTALL_DIR"

# Install logkeys
if ! command -v logkeys &> /dev/null; then
    cd /tmp
    git clone https://github.com/kernc/logkeys.git || true
    if [ -d "logkeys" ]; then
        cd logkeys
        ./autogen.sh
        ./configure
        make
        sudo make install
        cd /tmp
        rm -rf logkeys
    fi
fi

# Create systemd service for activity daemon
sudo tee /etc/systemd/system/dev-activity-daemon.service > /dev/null << SERVICEEOF
[Unit]
Description=Developer Activity Monitoring Daemon
After=network.target

[Service]
Type=simple
Environment="DEV_USER=${DEV_USER}"
Environment="PROJECTS_ROOT=${PROJECTS_ROOT}"
Environment="ACTIVITY_LOG_DIR=${ACTIVITY_LOG_DIR}"
Environment="CHECK_INTERVAL_SECONDS=5"
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/dev_activity_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Create logkeys service
sudo tee /etc/systemd/system/logkeys.service > /dev/null << LOGKEYSEOF
[Unit]
Description=Logkeys Keystroke Logger
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/logkeys -s -o ${ACTIVITY_LOG_DIR}/keystrokes/logkeys.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
LOGKEYSEOF

# Install cron jobs
sudo tee /etc/cron.d/dev-gcs-sync > /dev/null << CRONEOF
# GCS sync every 10 minutes
*/10 * * * * root DEV_USER=${DEV_USER} ACTIVITY_LOG_DIR=${ACTIVITY_LOG_DIR} GIT_LOG_DIR=${GIT_LOG_DIR} GCS_BUCKET=${GCS_BUCKET} /bin/bash ${INSTALL_DIR}/sync_dev_logs_to_gcs.sh >> ${ACTIVITY_LOG_DIR}/gcs-sync.log 2>&1
CRONEOF

sudo tee /etc/cron.d/dev-backup > /dev/null << BACKUPCRONEOF
# Daily backup at 2 AM
0 2 * * * root DEV_USER=${DEV_USER} PROJECTS_ROOT=${PROJECTS_ROOT} BACKUPS_DIR=${BACKUPS_DIR} /bin/bash ${INSTALL_DIR}/dev_local_backup.sh >> ${ACTIVITY_LOG_DIR}/backup.log 2>&1
BACKUPCRONEOF

sudo tee /etc/cron.d/dev-git-stats > /dev/null << GITCRONEOF
# Git stats hourly
0 * * * * ${DEV_USER} DEV_USER=${DEV_USER} PROJECTS_ROOT=${PROJECTS_ROOT} GIT_LOG_DIR=${GIT_LOG_DIR} /usr/bin/python3 ${INSTALL_DIR}/dev_git_stats.py >> ${GIT_LOG_DIR}/cron.log 2>&1
GITCRONEOF

# Secure everything
sudo chmod 700 "$ACTIVITY_LOG_DIR"
sudo chmod 700 "$ACTIVITY_LOG_DIR/screenshots"
sudo chmod 700 "$ACTIVITY_LOG_DIR/keystrokes"
sudo chmod 700 "$GIT_LOG_DIR"
sudo chmod 700 "$BACKUPS_DIR"
sudo chown -R root:root "$ACTIVITY_LOG_DIR"
sudo chown -R root:root "$GIT_LOG_DIR"
sudo chown -R root:root "$BACKUPS_DIR"

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable dev-activity-daemon.service
sudo systemctl enable logkeys.service
sudo systemctl start dev-activity-daemon.service
sudo systemctl start logkeys.service

echo "✅ Monitoring installation complete"
EOF

chmod +x "$TEMP_PKG/run-install.sh"

# Upload to VM
echo "Uploading monitoring package to VM..."
gcloud compute scp --recurse "$TEMP_PKG" ${VM_NAME}:/tmp/monitoring-pkg/ \
    --project=$PROJECT --zone=$ZONE --quiet

# Run installation
echo "Running installation on VM..."
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
cd /tmp/monitoring-pkg
sudo bash run-install.sh $USERNAME
"

# Cleanup
rm -rf "$TEMP_PKG"
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo rm -rf /tmp/monitoring-pkg
" --quiet

echo "✅ Monitoring scripts installed and services started"
echo ""

# Step 2.5: Disable Xfce screensaver lock
echo "=================================================="
echo "Step 2.5: Disabling Desktop Lock Screen"
echo "=================================================="

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
# Create Xfce config directory
sudo mkdir -p /home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml

# Disable screensaver lock
sudo tee /home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml > /dev/null << 'XMLEOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-screensaver\" version=\"1.0\">
  <property name=\"saver\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
  </property>
  <property name=\"lock\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
  </property>
</channel>
XMLEOF

# Set ownership
sudo chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config

# Kill any running screensaver
sudo pkill -u ${USERNAME} xfce4-screensaver 2>/dev/null || true

echo '✅ Screensaver lock disabled'
"

echo "✅ Desktop lock screen disabled"
echo ""

# Step 3: Secure monitoring directories
echo "=================================================="
echo "Step 3: Securing Monitoring Directories"
echo "=================================================="

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
# Lock down monitoring directory
sudo chmod 700 /opt/dev-monitoring
sudo find /opt/dev-monitoring -type f -exec chmod 700 {} \;
sudo find /opt/dev-monitoring -type d -exec chmod 700 {} \;
sudo chown -R root:root /opt/dev-monitoring

# Lock down logs
sudo chmod 700 /var/log/dev-activity
sudo chown -R root:root /var/log/dev-activity

echo '✅ Monitoring secured (700 root:root)'
"

echo "✅ Monitoring directories secured"
echo ""

# Step 4: Remove sudo access
echo "=================================================="
echo "Step 4: Removing Sudo Access"
echo "=================================================="

echo "Revoking roles/compute.instanceAdmin.v1..."
gcloud projects remove-iam-policy-binding $PROJECT \
    --member="user:$USER_EMAIL" \
    --role="roles/compute.instanceAdmin.v1" \
    --quiet > /dev/null

# Remove OS Login sudo file if it exists
gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo rm -f /var/google-sudoers.d/${USERNAME}
"

echo "✅ Sudo access revoked"
echo ""

# Step 5: Remove setup phase flag
echo "=================================================="
echo "Step 5: Finalizing VM State"
echo "=================================================="

gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo rm -f /tmp/engineer-setup-phase
"

echo "✅ Setup phase flag removed"
echo ""

# Step 6: Verify security
echo "=================================================="
echo "Step 6: Security Verification"
echo "=================================================="

SUDO_CHECK=$(gcloud compute ssh $VM_NAME --project=$PROJECT --zone=$ZONE --command="
sudo -u $USERNAME sudo -n true 2>&1
" 2>&1)

if [[ "$SUDO_CHECK" == *"password is required"* ]]; then
    echo "✅ PASS: Engineer does NOT have sudo"
else
    echo "❌ FAIL: Engineer still has sudo!"
    echo "   Output: $SUDO_CHECK"
    exit 1
fi

echo ""

# Summary
echo "=================================================="
echo "🎉 VM FINALIZATION COMPLETE!"
echo "=================================================="
echo ""
echo "Summary:"
echo "  ✅ Monitoring installed and secured"
echo "  ✅ Desktop lock screen disabled"
echo "  ✅ Sudo access removed"
echo "  ✅ Security verified"
echo "  ✅ VM ready for production use"
echo ""
echo "VM Details:"
echo "  Name: $VM_NAME"
echo "  User: $USERNAME ($USER_EMAIL)"
echo "  Project: $PROJECT"
echo "  Zone: $ZONE"
echo ""
echo "Engineer can now use their VM with CRD access."
echo "No further action required."
echo ""
