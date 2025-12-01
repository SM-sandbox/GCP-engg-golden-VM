#!/bin/bash
#
# Monitoring Installation Script
# Deploys activity daemon, git stats, backup, and GCS sync
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: Configuration file required${NC}"
    echo "Usage: $0 <config_file>"
    exit 1
fi

CONFIG_FILE="$1"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Monitoring Installation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Parse config
CONFIG_JSON=$(cat "$CONFIG_FILE" | yq eval -o=json 2>/dev/null || python3 -c "import yaml,sys,json; print(json.dumps(yaml.safe_load(sys.stdin)))" < "$CONFIG_FILE")

PROJECT_ID=$(echo "$CONFIG_JSON" | jq -r '.vm.project_id // .vm.project')
ZONE=$(echo "$CONFIG_JSON" | jq -r '.vm.zone')
VM_NAME=$(echo "$CONFIG_JSON" | jq -r '.vm.name')
DEV_USER=$(echo "$CONFIG_JSON" | jq -r '.users.developer.username // .user.username')
PROJECTS_ROOT=$(echo "$CONFIG_JSON" | jq -r '.paths.projects_root')
ACTIVITY_LOG_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.activity_log_dir')
GIT_LOG_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.git_log_dir')
BACKUPS_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.backups_dir')
GCS_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.gcs_sync.enabled // false')
GCS_BUCKET=$(echo "$CONFIG_JSON" | jq -r '.gcs_sync.bucket // ""')

INSTALL_DIR="/opt/dev-monitoring"

echo "Target VM: $VM_NAME"
echo "Developer: $DEV_USER"
echo "Installation directory: $INSTALL_DIR"
echo ""

# Create installation package
echo "Creating installation package..."
INSTALL_PACKAGE=$(mktemp -d)
cp "$SCRIPT_DIR"/dev_*.py "$INSTALL_PACKAGE/"
cp "$SCRIPT_DIR"/dev_*.sh "$INSTALL_PACKAGE/"
cp "$SCRIPT_DIR"/sync_*.sh "$INSTALL_PACKAGE/"

# Create install script
cat > "$INSTALL_PACKAGE/install.sh" << 'INSTALL_EOF'
#!/bin/bash
set -euo pipefail

DEV_USER="__DEV_USER__"
PROJECTS_ROOT="__PROJECTS_ROOT__"
ACTIVITY_LOG_DIR="__ACTIVITY_LOG_DIR__"
GIT_LOG_DIR="__GIT_LOG_DIR__"
BACKUPS_DIR="__BACKUPS_DIR__"
GCS_ENABLED="__GCS_ENABLED__"
GCS_BUCKET="__GCS_BUCKET__"
INSTALL_DIR="__INSTALL_DIR__"

echo "Installing monitoring tools..."

# Create installation directory
sudo mkdir -p "$INSTALL_DIR"
sudo cp *.py *.sh "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR"/*.py "$INSTALL_DIR"/*.sh

# Install Python dependencies and monitoring tools
echo "Installing Python dependencies and monitoring tools..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-psutil xprintidle wmctrl scrot build-essential autotools-dev autoconf kbd || {
    sudo pip3 install psutil
}

# Install logkeys for keystroke logging
echo "Installing logkeys for keystroke logging..."
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
        echo "✅ logkeys installed"
    else
        echo "⚠️  logkeys installation skipped (already installed or git clone failed)"
    fi
fi

# Start logkeys service
LOGKEYS_LOG_DIR="${ACTIVITY_LOG_DIR}/keystrokes"
sudo mkdir -p "$LOGKEYS_LOG_DIR"
sudo chmod 700 "$LOGKEYS_LOG_DIR"

# Create logkeys systemd service
sudo cat > /etc/systemd/system/logkeys.service << EOF
[Unit]
Description=Logkeys Keystroke Logger
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/logkeys -s -m /usr/share/logkeys/en_US.map -o ${LOGKEYS_LOG_DIR}/logkeys.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable logkeys.service
sudo systemctl restart logkeys.service

echo "✅ Logkeys service configured and started"

# Create log directories
sudo mkdir -p "$ACTIVITY_LOG_DIR" "$GIT_LOG_DIR" "$BACKUPS_DIR"
sudo chown -R $DEV_USER:$DEV_USER "$ACTIVITY_LOG_DIR" "$GIT_LOG_DIR" "$BACKUPS_DIR" || echo "⚠️  User $DEV_USER not found yet. Logs remain root-owned."
sudo chmod 755 "$ACTIVITY_LOG_DIR" "$GIT_LOG_DIR" "$BACKUPS_DIR"

# Install systemd service
# Install Permission Fixer Cron (Self-Healing for OS Login users)
echo "Installing permission fixer cron..."
cat > /etc/cron.d/dev-perm-fixer << CRON_EOF
*/5 * * * * root chown -R $DEV_USER:$DEV_USER "$ACTIVITY_LOG_DIR" "$GIT_LOG_DIR" "$BACKUPS_DIR" 2>/dev/null
CRON_EOF

echo "Installing activity monitoring service..."
cat > /tmp/dev-activity.service << SYSTEMD_EOF
[Unit]
Description=Developer Activity Monitoring Daemon
After=network.target

[Service]
Type=simple
User=root
Environment="DEV_USER=$DEV_USER"
Environment="PROJECTS_ROOT=$PROJECTS_ROOT"
Environment="ACTIVITY_LOG_DIR=$ACTIVITY_LOG_DIR"
Environment="CHECK_INTERVAL_SECONDS=60"
Environment="IDLE_SHUTDOWN_MINUTES=30"
Environment="CPU_IDLE_THRESHOLD=5.0"
Environment="GCS_BUCKET=$GCS_BUCKET"
ExecStart=/usr/bin/python3 $INSTALL_DIR/dev_activity_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

sudo mv /tmp/dev-activity.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dev-activity.service
sudo systemctl start dev-activity.service

echo "✓ Activity daemon installed and started"

# Install cron jobs
echo "Installing cron jobs..."

# Git stats - hourly
echo "0 * * * * $DEV_USER DEV_USER=$DEV_USER PROJECTS_ROOT=$PROJECTS_ROOT GIT_LOG_DIR=$GIT_LOG_DIR /usr/bin/python3 $INSTALL_DIR/dev_git_stats.py >> $GIT_LOG_DIR/cron.log 2>&1" | sudo tee /etc/cron.d/dev-git-stats >/dev/null

# Backup - daily at 2 AM
echo "0 2 * * * root DEV_USER=$DEV_USER PROJECTS_ROOT=$PROJECTS_ROOT BACKUPS_DIR=$BACKUPS_DIR RETENTION_DAYS=7 GCS_BUCKET=$GCS_BUCKET /bin/bash $INSTALL_DIR/dev_local_backup.sh >> $ACTIVITY_LOG_DIR/backup.log 2>&1" | sudo tee /etc/cron.d/dev-backup >/dev/null

# GCS sync - daily at 3 AM (if enabled)
if [[ "$GCS_ENABLED" == "true" ]]; then
    echo "0 3 * * * root DEV_USER=$DEV_USER ACTIVITY_LOG_DIR=$ACTIVITY_LOG_DIR GIT_LOG_DIR=$GIT_LOG_DIR GCS_BUCKET=$GCS_BUCKET RETENTION_DAYS=30 /bin/bash $INSTALL_DIR/sync_dev_logs_to_gcs.sh >> $ACTIVITY_LOG_DIR/gcs-sync.log 2>&1" | sudo tee /etc/cron.d/dev-gcs-sync >/dev/null
    echo "✓ GCS sync enabled"
else
    echo "⚠ GCS sync disabled"
fi

sudo chmod 644 /etc/cron.d/dev-*

echo "✓ Cron jobs installed"

# Configure shutdown permissions for activity daemon
echo "Configuring shutdown permissions..."
echo "$DEV_USER ALL=NOPASSWD: /sbin/shutdown" | sudo tee /etc/sudoers.d/dev-shutdown >/dev/null
echo "root ALL=NOPASSWD: /sbin/shutdown" | sudo tee -a /etc/sudoers.d/dev-shutdown >/dev/null
sudo chmod 440 /etc/sudoers.d/dev-shutdown

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Monitoring installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Status:"
echo "  Activity Daemon: systemctl status dev-activity"
echo "  Logs: journalctl -u dev-activity -f"
echo ""
INSTALL_EOF

# Replace placeholders
sed -i.bak "s|__DEV_USER__|$DEV_USER|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__PROJECTS_ROOT__|$PROJECTS_ROOT|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__ACTIVITY_LOG_DIR__|$ACTIVITY_LOG_DIR|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__GIT_LOG_DIR__|$GIT_LOG_DIR|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__BACKUPS_DIR__|$BACKUPS_DIR|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__GCS_ENABLED__|$GCS_ENABLED|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__GCS_BUCKET__|$GCS_BUCKET|g" "$INSTALL_PACKAGE/install.sh"
sed -i.bak "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$INSTALL_PACKAGE/install.sh"
rm "$INSTALL_PACKAGE/install.sh.bak"

chmod +x "$INSTALL_PACKAGE/install.sh"

# Copy to VM and execute
echo "Uploading to VM..."
gcloud compute scp --recurse "$INSTALL_PACKAGE"/* "$VM_NAME:/tmp/monitoring-install/" --zone="$ZONE" --project="$PROJECT_ID" --quiet

echo "Installing on VM..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --ssh-flag="-t" --command="cd /tmp/monitoring-install && sudo bash install.sh"

# Cleanup
rm -rf "$INSTALL_PACKAGE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Monitoring Deployed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Check status:"
echo "  gcloud compute ssh $VM_NAME --zone=$ZONE --command='sudo systemctl status dev-activity'"
echo ""
