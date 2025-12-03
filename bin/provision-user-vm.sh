#!/bin/bash
#
# PROVISION USER VM - Complete Workflow
# This script ensures ALL artifacts are created when provisioning a new user VM:
# 1. Static IP
# 2. VM from golden image
# 3. User account on VM
# 4. Monitoring configuration
# 5. GCS folder
# 6. Config YAML file
# 7. Onboarding email
#
# Usage: ./provision-user-vm.sh <username> [email]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
PROJECT="gcp-engg-vm"
ZONE="us-east1-b"
REGION="us-east1"
MACHINE_TYPE="n2-standard-4"
DISK_SIZE="100GB"
GOLDEN_IMAGE="gcp-engg-golden-v3-production-20251203"
GCS_BUCKET="brightfox-dev-logs"
DEFAULT_PASSWORD="bfAI2025vmtest!"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() { echo -e "${GREEN}[STEP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate input
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <username> [email]"
    echo "Example: $0 akash akash@brightfox.ai"
    exit 1
fi

USERNAME="$1"
EMAIL="${2:-${USERNAME}@brightfox.ai}"
VM_NAME="dev-${USERNAME}-gnome-nm-001"
IP_NAME="${VM_NAME}-ip"

echo "========================================"
echo "  PROVISIONING USER VM"
echo "========================================"
echo "Username:    $USERNAME"
echo "Email:       $EMAIL"
echo "VM Name:     $VM_NAME"
echo "Project:     $PROJECT"
echo "Zone:        $ZONE"
echo "Image:       $GOLDEN_IMAGE"
echo "========================================"
echo ""

# Step 1: Create static IP
log_step "1/7 Creating static IP..."
if gcloud compute addresses describe "$IP_NAME" --project="$PROJECT" --region="$REGION" &>/dev/null; then
    log_warn "Static IP $IP_NAME already exists"
    STATIC_IP=$(gcloud compute addresses describe "$IP_NAME" --project="$PROJECT" --region="$REGION" --format="value(address)")
else
    gcloud compute addresses create "$IP_NAME" --project="$PROJECT" --region="$REGION"
    STATIC_IP=$(gcloud compute addresses describe "$IP_NAME" --project="$PROJECT" --region="$REGION" --format="value(address)")
fi
echo "   Static IP: $STATIC_IP"

# Step 2: Create VM
log_step "2/7 Creating VM from golden image..."
if gcloud compute instances describe "$VM_NAME" --project="$PROJECT" --zone="$ZONE" &>/dev/null; then
    log_warn "VM $VM_NAME already exists"
else
    gcloud compute instances create "$VM_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image="$GOLDEN_IMAGE" \
        --image-project="$PROJECT" \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type=pd-balanced \
        --address="$STATIC_IP" \
        --scopes=storage-rw,logging-write,monitoring-write \
        --tags=nomachine,http-server,https-server
fi

# Wait for VM to be ready
echo "   Waiting for VM to boot..."
sleep 30

# Step 3: Configure user on VM
log_step "3/7 Configuring user account on VM..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --command="
# Create user
sudo useradd -m -s /bin/bash $USERNAME 2>/dev/null || true
echo '$USERNAME:$DEFAULT_PASSWORD' | sudo chpasswd

# Configure monitoring
sudo sed -i 's/__DEV_USER__/$USERNAME/g' /etc/systemd/system/dev-activity.service
sudo sed -i 's/__DEV_USER__/$USERNAME/g' /opt/dev-monitoring/run_sync.sh
sudo sed -i 's/__DEV_USER__/$USERNAME/g' /opt/dev-monitoring/screen_recorder.sh

# Set up cron for sync
(crontab -l 2>/dev/null | grep -v run_sync; echo '*/5 * * * * /opt/dev-monitoring/run_sync.sh >> /var/log/dev-activity/gcs-sync.log 2>&1') | crontab -

# Reload and start services
sudo systemctl daemon-reload
sudo systemctl restart dev-activity
sudo systemctl restart screen-recorder
"

# Step 4: Create GCS folder
log_step "4/7 Creating GCS folder..."
gsutil cp /dev/null "gs://${GCS_BUCKET}/${USERNAME}/.keep" 2>/dev/null || true

# Step 5: Create config YAML
log_step "5/7 Creating config YAML..."
CONFIG_FILE="$REPO_ROOT/config/users/${USERNAME}.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
    log_warn "Config file already exists: $CONFIG_FILE"
else
    cat > "$CONFIG_FILE" << EOF
# ${USERNAME^}'s Developer VM Configuration
# Created: $(date +%Y-%m-%d)

vm:
  name: $VM_NAME
  project_id: $PROJECT
  zone: $ZONE
  machine_type: $MACHINE_TYPE
  disk_size_gb: ${DISK_SIZE%GB}
  static_ip: $STATIC_IP
  image_family: gcp-engg-golden-v3

user:
  username: $USERNAME
  email: $EMAIL
  default_password: $DEFAULT_PASSWORD

paths:
  projects: /home/$USERNAME/projects
  logs: /var/log/dev-activity
  backups: /home/$USERNAME/backups

gcs_sync:
  bucket: $GCS_BUCKET
  prefix: $USERNAME
  interval_minutes: 5
EOF
fi

# Step 6: Create onboarding email
log_step "6/7 Creating onboarding email..."
EMAIL_FILE="$REPO_ROOT/docs/onboarding/onboarding-email-${USERNAME}.txt"
if [[ -f "$EMAIL_FILE" ]]; then
    log_warn "Onboarding email already exists: $EMAIL_FILE"
else
    cat > "$EMAIL_FILE" << EOF
================================================================================
DEVELOPER VM ONBOARDING - ${USERNAME^^}
================================================================================

Hi ${USERNAME^},

Your secure development VM is ready! Here's everything you need to get started.

--------------------------------------------------------------------------------
YOUR VM DETAILS
--------------------------------------------------------------------------------

VM Name:        $VM_NAME
Static IP:      $STATIC_IP
NoMachine Port: 4000
Username:       $USERNAME
Password:       $DEFAULT_PASSWORD

--------------------------------------------------------------------------------
STEP 1: INSTALL GOOGLE CLOUD CLI (One-time setup)
--------------------------------------------------------------------------------

If you don't have gcloud installed:

1. Download from: https://cloud.google.com/sdk/docs/install
2. Install and restart Terminal

--------------------------------------------------------------------------------
STEP 2: AUTHENTICATE WITH GOOGLE CLOUD (One-time setup)
--------------------------------------------------------------------------------

1. Open Terminal on your Mac

2. Run this command:
   gcloud auth login --no-launch-browser

3. Copy the URL it gives you and paste it into your browser

4. Sign in with your Brightfox Google account

5. Copy the authorization code back into Terminal

--------------------------------------------------------------------------------
STEP 3: START YOUR VM
--------------------------------------------------------------------------------

Your VM shuts down automatically when idle to save costs. Start it with:

   gcloud compute instances start $VM_NAME --zone=$ZONE --project=$PROJECT

--------------------------------------------------------------------------------
STEP 4: VERIFY VM IS READY (Important!)
--------------------------------------------------------------------------------

Before connecting with NoMachine, confirm the VM is fully booted:

   gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="echo 'VM is ready!' && systemctl is-active nxserver"

You should see:
   VM is ready!
   active

If you see "active", proceed to Step 5. If not, wait 30 seconds and try again.

--------------------------------------------------------------------------------
STEP 5: INSTALL NOMACHINE (One-time setup)
--------------------------------------------------------------------------------

1. Download NoMachine from: https://downloads.nomachine.com/download/?id=3

2. Install it on your Mac (drag to Applications)

3. Open NoMachine

--------------------------------------------------------------------------------
STEP 6: CONNECT TO YOUR VM
--------------------------------------------------------------------------------

1. In NoMachine, click "Add" to create a new connection

2. Enter these details:
   - Name: ${USERNAME^} Dev VM
   - Host: $STATIC_IP
   - Port: 4000
   - Protocol: NX
   - Check "Always accept the host verification key"

3. Click "Add", then double-click your new connection

4. When prompted, enter:
   - Username: $USERNAME
   - Password: $DEFAULT_PASSWORD

5. If asked to "create a new display", click Yes

6. You'll see the Ubuntu GNOME desktop!

--------------------------------------------------------------------------------
STEP 7: CHANGE YOUR PASSWORD (Optional but Recommended)
--------------------------------------------------------------------------------

Once logged into the desktop:

1. Open Terminal (click Activities, type "Terminal")

2. Run: passwd

3. Enter current password: $DEFAULT_PASSWORD

4. Enter your new password twice

--------------------------------------------------------------------------------
WHAT'S INSTALLED
--------------------------------------------------------------------------------

Your VM comes pre-loaded with:

Development Tools:
- Windsurf IDE (AI-powered code editor)
- Git
- Python 3.10 + pip
- Node.js 20 + npm
- Build essentials (gcc, make)

Cloud CLIs:
- Google Cloud CLI (gcloud)
- Azure CLI (az)
- Azure Developer CLI (azd)
- GitHub CLI (gh)

Browsers:
- Google Chrome

Remote Desktop:
- NoMachine server

--------------------------------------------------------------------------------
DAILY WORKFLOW
--------------------------------------------------------------------------------

START YOUR DAY:
   gcloud compute instances start $VM_NAME --zone=$ZONE --project=$PROJECT

VERIFY IT'S READY:
   gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="systemctl is-active nxserver"

CONNECT: Open NoMachine and double-click "${USERNAME^} Dev VM"

END YOUR DAY (optional - VM auto-shuts down after 30 min idle):
   gcloud compute instances stop $VM_NAME --zone=$ZONE --project=$PROJECT

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------

1. AUTO-SHUTDOWN: Your VM automatically shuts down after 30 minutes of 
   inactivity to save costs. Just start it again when you need it.

2. STATIC IP: Your IP address ($STATIC_IP) never changes, so your 
   NoMachine connection will always work.

3. YOUR PROJECTS: Save your work in ~/projects - this is your workspace.

4. UBUNTU PROMPTS: If you see prompts about Ubuntu Pro or upgrading to 
   24.04, click "Skip" or "Don't Upgrade". We manage updates centrally.

--------------------------------------------------------------------------------
NEED HELP?
--------------------------------------------------------------------------------

If you run into any issues, reach out on Teams and we'll get you sorted.

Welcome to your new dev environment!

================================================================================
EOF
fi

# Step 7: Summary
log_step "7/7 Complete!"
echo ""
echo "========================================"
echo "  PROVISIONING COMPLETE"
echo "========================================"
echo ""
echo "VM Details:"
echo "  Name:     $VM_NAME"
echo "  IP:       $STATIC_IP"
echo "  Username: $USERNAME"
echo "  Password: $DEFAULT_PASSWORD"
echo ""
echo "Files Created:"
echo "  Config:   $CONFIG_FILE"
echo "  Email:    $EMAIL_FILE"
echo ""
echo "GCS Folder: gs://${GCS_BUCKET}/${USERNAME}/"
echo ""
echo "Next Steps:"
echo "  1. Review the onboarding email: $EMAIL_FILE"
echo "  2. Send to user via Teams"
echo "  3. Commit changes to git"
echo "========================================"
