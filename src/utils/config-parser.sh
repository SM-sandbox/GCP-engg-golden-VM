#!/bin/bash
#
# Environment Provisioning Script
# Installs packages, sets up directories, clones repos - all config-driven
#
# Usage: ./ensure_env_from_config.sh <config_file>
# Example: ./ensure_env_from_config.sh ../config/users/jerry.yaml
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
echo -e "${BLUE}  Environment Provisioning${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Parse config
CONFIG_JSON=$(cat "$CONFIG_FILE" | yq eval -o=json 2>/dev/null || python3 -c "import yaml,sys,json; print(json.dumps(yaml.safe_load(sys.stdin)))" < "$CONFIG_FILE")

PROJECT_ID=$(echo "$CONFIG_JSON" | jq -r '.vm.project_id')
ZONE=$(echo "$CONFIG_JSON" | jq -r '.vm.zone')
VM_NAME=$(echo "$CONFIG_JSON" | jq -r '.vm.name')
DEV_USER=$(echo "$CONFIG_JSON" | jq -r '.users.developer.username')
DEV_EMAIL=$(echo "$CONFIG_JSON" | jq -r '.users.developer.email // "dev@example.com"')

echo "Target VM: $VM_NAME ($PROJECT_ID / $ZONE)"
echo "Developer: $DEV_USER"
echo ""

# Create temporary setup script
SETUP_SCRIPT=$(mktemp)
cat > "$SETUP_SCRIPT" << 'SETUP_EOF'
#!/bin/bash
set -euo pipefail

CONFIG_JSON='__CONFIG_JSON__'
DEV_USER='__DEV_USER__'
DEV_EMAIL='__DEV_EMAIL__'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  System Package Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Update package lists
echo "Updating package lists..."
sudo apt-get update -qq

# Install apt packages
echo "Installing system packages..."
APT_PACKAGES=$(echo "$CONFIG_JSON" | jq -r '.system_packages.apt[]' | tr '\n' ' ')
if [[ -n "$APT_PACKAGES" ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_PACKAGES
    echo "✓ System packages installed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud SDK Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Install Cloud SDKs
CLOUD_SDKS=$(echo "$CONFIG_JSON" | jq -r '.system_packages.cloud_sdks[]' 2>/dev/null || echo "")

for sdk in $CLOUD_SDKS; do
    echo "Installing $sdk..."
    case $sdk in
        gcloud)
            if ! command -v gcloud &>/dev/null; then
                echo "  Installing Google Cloud SDK..."
                curl -sS https://sdk.cloud.google.com | bash -s -- --disable-prompts >/dev/null 2>&1
                export PATH="$HOME/google-cloud-sdk/bin:$PATH"
                echo "  ✓ gcloud installed"
            else
                echo "  ✓ gcloud already installed"
            fi
            ;;
        gh)
            if ! command -v gh &>/dev/null; then
                echo "  Installing GitHub CLI..."
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt-get update -qq
                sudo apt-get install -y gh
                echo "  ✓ gh installed"
            else
                echo "  ✓ gh already installed"
            fi
            ;;
        az)
            if ! command -v az &>/dev/null; then
                echo "  Installing Azure CLI..."
                curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
                echo "  ✓ az installed"
            else
                echo "  ✓ az already installed"
            fi
            ;;
        azd)
            if ! command -v azd &>/dev/null; then
                echo "  Installing Azure Developer CLI..."
                curl -fsSL https://aka.ms/install-azd.sh | bash
                echo "  ✓ azd installed"
            else
                echo "  ✓ azd already installed"
            fi
            ;;
    esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Optional Languages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Go
GO_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.languages.go.enabled // false')
if [[ "$GO_ENABLED" == "true" ]]; then
    GO_VERSION=$(echo "$CONFIG_JSON" | jq -r '.languages.go.version // "1.22"')
    echo "Installing Go $GO_VERSION..."
    if [[ ! -d /usr/local/go ]]; then
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
        sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
        rm "go${GO_VERSION}.linux-amd64.tar.gz"
        echo "  ✓ Go $GO_VERSION installed"
    else
        echo "  ✓ Go already installed"
    fi
else
    echo "Go: disabled"
fi

# Check Rust
RUST_ENABLED=$(echo "$CONFIG_JSON" | jq -r '.languages.rust.enabled // false')
if [[ "$RUST_ENABLED" == "true" ]]; then
    echo "Installing Rust..."
    if ! command -v rustc &>/dev/null; then
        sudo -u "$DEV_USER" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
        echo "  ✓ Rust installed"
    else
        echo "  ✓ Rust already installed"
    fi
else
    echo "Rust: disabled"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Developer Directory Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create directories
DIRS=$(echo "$CONFIG_JSON" | jq -r '.developer_setup.create_dirs[]' 2>/dev/null || echo "")
for dir_key in $DIRS; do
    DIR_PATH=$(echo "$CONFIG_JSON" | jq -r ".paths.${dir_key}")
    echo "Creating: $DIR_PATH"
    sudo -u "$DEV_USER" mkdir -p "$DIR_PATH"
done

# Create system directories (require sudo)
BACKUPS_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.backups_dir')
ACTIVITY_LOG_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.activity_log_dir')
GIT_LOG_DIR=$(echo "$CONFIG_JSON" | jq -r '.paths.git_log_dir')

sudo mkdir -p "$BACKUPS_DIR" "$ACTIVITY_LOG_DIR" "$GIT_LOG_DIR"
sudo chown -R "$DEV_USER:$DEV_USER" "$BACKUPS_DIR"
sudo chmod 755 "$BACKUPS_DIR"

echo "✓ Directory structure created"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Python Virtual Environments"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create Python venvs
ENVS_ROOT=$(echo "$CONFIG_JSON" | jq -r '.paths.envs_root')
VENV_COUNT=$(echo "$CONFIG_JSON" | jq '.developer_setup.python_envs | length' 2>/dev/null || echo "0")

if [[ "$VENV_COUNT" -gt 0 ]]; then
    for i in $(seq 0 $((VENV_COUNT - 1))); do
        VENV_NAME=$(echo "$CONFIG_JSON" | jq -r ".developer_setup.python_envs[$i].name")
        VENV_PATH="$ENVS_ROOT/$VENV_NAME"
        
        echo "Creating venv: $VENV_NAME"
        sudo -u "$DEV_USER" python3 -m venv "$VENV_PATH"
        
        # Install packages
        PACKAGES=$(echo "$CONFIG_JSON" | jq -r ".developer_setup.python_envs[$i].packages[]" | tr '\n' ' ')
        if [[ -n "$PACKAGES" ]]; then
            echo "  Installing packages: $PACKAGES"
            sudo -u "$DEV_USER" bash -c "source $VENV_PATH/bin/activate && pip install --quiet $PACKAGES"
        fi
        echo "  ✓ $VENV_NAME ready"
    done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Shell Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Update .bashrc
BASHRC="/home/$DEV_USER/.bashrc"
BIN_ROOT=$(echo "$CONFIG_JSON" | jq -r '.paths.bin_root')

sudo -u "$DEV_USER" bash << 'BASHRC_EOF'
BASHRC="/home/$DEV_USER/.bashrc"
BIN_ROOT="$BIN_ROOT"

# Add custom PATH
if ! grep -q "# Dev VM Custom Paths" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOF'

# Dev VM Custom Paths
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# Go (if installed)
if [ -d /usr/local/go ]; then
    export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"
    export GOPATH="$HOME/go"
fi

# Rust (if installed)
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Git configuration
git config --global user.email "$DEV_EMAIL" 2>/dev/null || true
git config --global user.name "$DEV_USER" 2>/dev/null || true

# Helpful aliases
alias ll='ls -alh'
alias python=python3
alias pip=pip3

EOF
fi
BASHRC_EOF

echo "✓ Shell configuration updated"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repository Cloning"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clone repositories
PROJECTS_ROOT=$(echo "$CONFIG_JSON" | jq -r '.paths.projects_root')
REPOS=$(echo "$CONFIG_JSON" | jq -r '.repos[]' 2>/dev/null || echo "")

if [[ -n "$REPOS" ]]; then
    for repo in $REPOS; do
        REPO_NAME=$(basename "$repo")
        REPO_PATH="$PROJECTS_ROOT/$REPO_NAME"
        
        if [[ -d "$REPO_PATH" ]]; then
            echo "  ✓ $repo (already cloned)"
        else
            echo "  Cloning $repo..."
            sudo -u "$DEV_USER" git clone "git@github.com:$repo.git" "$REPO_PATH" 2>/dev/null || {
                echo "  ⚠ Clone failed (check deploy key)"
            }
        fi
    done
else
    echo "No repositories configured"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Environment provisioning complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SETUP_EOF

# Replace placeholders
sed -i.bak "s|__CONFIG_JSON__|$(echo "$CONFIG_JSON" | sed 's/|/\\|/g')|g" "$SETUP_SCRIPT"
sed -i.bak "s|__DEV_USER__|$DEV_USER|g" "$SETUP_SCRIPT"
sed -i.bak "s|__DEV_EMAIL__|$DEV_EMAIL|g" "$SETUP_SCRIPT"
rm "${SETUP_SCRIPT}.bak"

# Copy to VM and execute
echo "Uploading setup script to VM..."
gcloud compute scp "$SETUP_SCRIPT" "$VM_NAME:/tmp/setup.sh" --zone="$ZONE" --quiet

echo "Executing setup script on VM..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --command="chmod +x /tmp/setup.sh && sudo /tmp/setup.sh"

# Cleanup
rm "$SETUP_SCRIPT"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Environment Ready!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next: Install monitoring"
echo "  ./vm-scripts/install_monitoring.sh $CONFIG_FILE"
echo ""
