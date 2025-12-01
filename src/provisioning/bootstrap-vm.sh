#!/bin/bash
#
# Developer VM Bootstrap Script
# Provisions a complete GCP VM with users, SSH keys, and GitHub deploy keys
#
# Usage: ./bootstrap_dev_vm.sh <config_file>
# Example: ./bootstrap_dev_vm.sh ../config/users/jerry.yaml
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse command line arguments
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: Configuration file required${NC}"
    echo "Usage: $0 <config_file>"
    echo "Example: $0 ../config/users/jerry.yaml"
    exit 1
fi

CONFIG_FILE="$1"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Developer VM Bootstrap${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Config: ${CYAN}$CONFIG_FILE${NC}"
echo ""

# Dependency check
echo "Checking dependencies..."
for cmd in gcloud gh yq jq ssh; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}✗ Missing required command: $cmd${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ All dependencies present${NC}"
echo ""

# Parse YAML config using yq (install via: brew install yq)
# If yq not available, we'll use Python
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}Note: yq not found, using Python to parse YAML${NC}"
    PARSE_CMD="python3 -c \"import yaml,sys,json; print(json.dumps(yaml.safe_load(sys.stdin)))\""
else
    PARSE_CMD="yq eval -o=json"
fi

# Read configuration
echo "Parsing configuration..."
CONFIG_JSON=$(cat "$CONFIG_FILE" | yq eval -o=json 2>/dev/null || python3 -c "import yaml,sys,json; print(json.dumps(yaml.safe_load(sys.stdin)))" < "$CONFIG_FILE")

# Extract values
PROJECT_ID=$(echo "$CONFIG_JSON" | jq -r '.vm.project_id')
ZONE=$(echo "$CONFIG_JSON" | jq -r '.vm.zone')
VM_NAME=$(echo "$CONFIG_JSON" | jq -r '.vm.name')
MACHINE_TYPE=$(echo "$CONFIG_JSON" | jq -r '.vm.machine_type')
BOOT_DISK_GB=$(echo "$CONFIG_JSON" | jq -r '.vm.boot_disk_gb')
OS_IMAGE=$(echo "$CONFIG_JSON" | jq -r '.vm.os_image')
ADMIN_USER=$(echo "$CONFIG_JSON" | jq -r '.users.admin.username')
DEV_USER=$(echo "$CONFIG_JSON" | jq -r '.users.developer.username')
DEV_EMAIL=$(echo "$CONFIG_JSON" | jq -r '.users.developer.email // "dev@example.com"')

echo -e "${GREEN}✓ Configuration loaded${NC}"
echo "  Project: $PROJECT_ID"
echo "  Zone: $ZONE"
echo "  VM: $VM_NAME"
echo "  Admin: $ADMIN_USER"
echo "  Developer: $DEV_USER"
echo ""

# Step 1: Create or verify GCP project
echo -e "${CYAN}Step 1: Project Setup${NC}"
if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo -e "${GREEN}✓ Project exists${NC}: $PROJECT_ID"
else
    echo -e "${YELLOW}Creating new project: $PROJECT_ID${NC}"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gcloud projects create "$PROJECT_ID" --name="$PROJECT_ID"
        echo -e "${GREEN}✓ Project created${NC}"
    else
        echo "Aborted."
        exit 1
    fi
fi

# Set default project
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo "Enabling required APIs..."
APIS=(
    "compute.googleapis.com"
    "storage-api.googleapis.com"
    "storage-component.googleapis.com"
)

for api in "${APIS[@]}"; do
    echo -n "  Enabling $api... "
    gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null || true
    echo "done"
done
echo ""

# Step 2: Create VM instance
echo -e "${CYAN}Step 2: VM Creation${NC}"
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
    echo -e "${YELLOW}⚠ VM already exists${NC}: $VM_NAME"
    read -p "Recreate? This will DELETE the existing VM (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing VM..."
        gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --quiet
    else
        echo "Using existing VM..."
    fi
fi

if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
    echo "Creating VM: $VM_NAME"
    
    # Determine OS image
    if [[ "$OS_IMAGE" == "ubuntu-2204-lts" ]]; then
        IMAGE_FAMILY="ubuntu-2204-lts"
        IMAGE_PROJECT="ubuntu-os-cloud"
    else
        IMAGE_FAMILY="$OS_IMAGE"
        IMAGE_PROJECT="ubuntu-os-cloud"
    fi
    
    gcloud compute instances create "$VM_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --boot-disk-size="${BOOT_DISK_GB}GB" \
        --boot-disk-type=pd-standard \
        --image-family="$IMAGE_FAMILY" \
        --image-project="$IMAGE_PROJECT" \
        --scopes=cloud-platform \
        --metadata=enable-oslogin=FALSE \
        --tags=dev-vm
    
    echo -e "${GREEN}✓ VM created${NC}"
    
    echo "Waiting 30 seconds for VM to fully boot..."
    sleep 30
else
    echo -e "${GREEN}✓ VM ready${NC}"
fi
echo ""

# Step 3: Get VM IP
echo -e "${CYAN}Step 3: VM Connection${NC}"
VM_IP=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
echo "VM IP: $VM_IP"

# Test SSH connectivity
echo -n "Testing SSH connectivity... "
if timeout 10 gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="echo connected" &>/dev/null; then
    echo -e "${GREEN}✓ Connected${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
    echo "Wait a moment and try running this script again."
    exit 1
fi
echo ""

# Step 4: Create Linux users
echo -e "${CYAN}Step 4: User Creation${NC}"

# Create admin user (with sudo)
echo "Creating admin user: $ADMIN_USER"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="
    sudo useradd -m -s /bin/bash -G sudo $ADMIN_USER 2>/dev/null || true
    echo '$ADMIN_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$ADMIN_USER >/dev/null
    sudo mkdir -p /home/$ADMIN_USER/.ssh
    sudo chmod 700 /home/$ADMIN_USER/.ssh
    sudo chown -R $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER
" >/dev/null

echo -e "${GREEN}✓ Admin user created${NC}: $ADMIN_USER (sudo access)"

# Create developer user (no sudo)
echo "Creating developer user: $DEV_USER"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="
    sudo useradd -m -s /bin/bash $DEV_USER 2>/dev/null || true
    sudo mkdir -p /home/$DEV_USER/.ssh
    sudo chmod 700 /home/$DEV_USER/.ssh
    sudo chown -R $DEV_USER:$DEV_USER /home/$DEV_USER
" >/dev/null

echo -e "${GREEN}✓ Developer user created${NC}: $DEV_USER (no sudo)"
echo ""

# Step 5: Generate SSH key for developer (for GitHub)
echo -e "${CYAN}Step 5: GitHub SSH Key${NC}"
echo "Generating SSH key on VM for $DEV_USER..."

gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="
    sudo -u $DEV_USER ssh-keygen -t ed25519 -C '$DEV_EMAIL' -f /home/$DEV_USER/.ssh/id_ed25519 -N '' <<<y >/dev/null 2>&1
    sudo chmod 600 /home/$DEV_USER/.ssh/id_ed25519
    sudo chmod 644 /home/$DEV_USER/.ssh/id_ed25519.pub
" >/dev/null

echo -e "${GREEN}✓ SSH key generated${NC}"

# Retrieve public key
echo "Retrieving public key..."
SSH_PUBLIC_KEY=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="sudo cat /home/$DEV_USER/.ssh/id_ed25519.pub")
echo "Public key: ${SSH_PUBLIC_KEY:0:60}..."

# Save to local file for reference
mkdir -p "$REPO_ROOT/.keys"
echo "$SSH_PUBLIC_KEY" > "$REPO_ROOT/.keys/${DEV_USER}_${VM_NAME}.pub"
echo -e "${GREEN}✓ Key saved${NC} to .keys/${DEV_USER}_${VM_NAME}.pub"
echo ""

# Step 6: Register GitHub deploy keys
echo -e "${CYAN}Step 6: GitHub Deploy Keys${NC}"
REPOS=$(echo "$CONFIG_JSON" | jq -r '.repos[]')

if [[ -z "$REPOS" ]]; then
    echo -e "${YELLOW}⚠ No repositories configured${NC}"
else
    for repo in $REPOS; do
        echo "Adding deploy key for $repo..."
        
        # Check if key already exists
        EXISTING_KEYS=$(gh repo deploy-key list --repo "$repo" 2>/dev/null || echo "")
        KEY_TITLE="${DEV_USER}@${VM_NAME}"
        
        if echo "$EXISTING_KEYS" | grep -q "$KEY_TITLE"; then
            echo -e "  ${YELLOW}⚠ Key already exists${NC}"
        else
            gh repo deploy-key add "$REPO_ROOT/.keys/${DEV_USER}_${VM_NAME}.pub" \
                --repo "$repo" \
                --title "$KEY_TITLE" \
                --allow-write
            echo -e "  ${GREEN}✓ Deploy key added${NC}"
        fi
    done
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Bootstrap Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next steps:"
echo "  1. Run: ./ensure_env_from_config.sh $CONFIG_FILE"
echo "  2. SSH into VM: gcloud compute ssh $VM_NAME --zone=$ZONE"
echo ""
