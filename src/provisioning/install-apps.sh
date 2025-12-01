#!/bin/bash
set -e

# Application Installation Script
# Usage: ./install-apps.sh [--chrome] [--windsurf] [--jupyter] [--python] [--node] [--git] [--utils] [--build-tools]

INSTALL_CHROME=false
INSTALL_WINDSURF=false
INSTALL_JUPYTER=false
INSTALL_PYTHON=false
INSTALL_NODE=false
INSTALL_GIT=false
INSTALL_UTILS=false
INSTALL_BUILD_TOOLS=false
INSTALL_GITHUB_CLI=false
INSTALL_AZURE_CLI=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --chrome) INSTALL_CHROME=true ;;
        --windsurf) INSTALL_WINDSURF=true ;;
        --jupyter) INSTALL_JUPYTER=true ;;
        --python) INSTALL_PYTHON=true ;;
        --node) INSTALL_NODE=true ;;
        --git) INSTALL_GIT=true ;;
        --utils) INSTALL_UTILS=true ;;
        --build-tools) INSTALL_BUILD_TOOLS=true ;;
        --github-cli) INSTALL_GITHUB_CLI=true ;;
        --azure-cli) INSTALL_AZURE_CLI=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

echo "=================================================="
echo "📦 Installing User Applications & Tools"
echo "=================================================="

# 0. Standard Utilities (Zip, Curl, Wget, etc)
if [ "$INSTALL_UTILS" = true ]; then
    echo "➡️  Installing System Utilities..."
    sudo apt-get install -y curl wget zip unzip htop software-properties-common gnupg2 apt-transport-https ca-certificates lsb-release
    echo "✅ Utilities installed"
    echo ""
fi

# 1. Git
if [ "$INSTALL_GIT" = true ]; then
    echo "➡️  Installing Git..."
    sudo apt-get install -y git
    echo "✅ Git installed"
    echo ""
fi

# 1.1 GitHub CLI (gh)
if [ "$INSTALL_GITHUB_CLI" = true ]; then
    echo "➡️  Installing GitHub CLI (gh)..."
    if ! command -v gh >/dev/null 2>&1; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
        && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt-get update \
        && sudo apt-get install -y gh
        echo "✅ GitHub CLI installed"
    else
        echo "✅ GitHub CLI already installed"
    fi
    echo ""
fi

# 1.2 Azure CLI & AZD
if [ "$INSTALL_AZURE_CLI" = true ]; then
    echo "➡️  Installing Azure CLI (az) & AZD..."
    
    # Install Azure CLI (az)
    if ! command -v az >/dev/null 2>&1; then
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        echo "✅ Azure CLI (az) installed"
    else
        echo "✅ Azure CLI (az) already installed"
    fi

    # Install Azure Developer CLI (azd)
    if ! command -v azd >/dev/null 2>&1; then
        curl -fsSL https://aka.ms/install-azd.sh | sudo bash
        echo "✅ Azure Developer CLI (azd) installed"
    else
        echo "✅ Azure Developer CLI (azd) already installed"
    fi
    echo ""
fi

# 2. Build Tools (GCC, Make)
if [ "$INSTALL_BUILD_TOOLS" = true ]; then
    echo "➡️  Installing Build Essentials..."
    sudo apt-get install -y build-essential
    echo "✅ Build Essentials installed"
    echo ""
fi

# 3. Python Environment
if [ "$INSTALL_PYTHON" = true ]; then
    echo "➡️  Installing Python 3, Pip, Venv..."
    sudo apt-get install -y python3 python3-pip python3-venv
    echo "✅ Python environment installed"
    echo ""
fi

# 4. Node.js (LTS)
if [ "$INSTALL_NODE" = true ]; then
    echo "➡️  Installing Node.js (LTS)..."
    if ! command -v node >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
        echo "✅ Node.js installed"
    else
        echo "✅ Node.js already installed"
    fi
    echo ""
fi

# 5. Google Chrome
if [ "$INSTALL_CHROME" = true ]; then
    echo "➡️  Installing Google Chrome..."
    if ! command -v google-chrome >/dev/null 2>&1; then
        wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        sudo apt-get install -y ./google-chrome-stable_current_amd64.deb
        rm google-chrome-stable_current_amd64.deb
        echo "✅ Google Chrome installed"
    else
        echo "✅ Google Chrome already installed"
    fi
    echo ""
fi

# 6. Windsurf IDE
if [ "$INSTALL_WINDSURF" = true ]; then
    echo "➡️  Installing Windsurf..."
    if ! command -v windsurf >/dev/null 2>&1; then
        # Add GPG key
        curl -fsSL "https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/windsurf.gpg" | sudo gpg --dearmor -o /usr/share/keyrings/windsurf-stable-archive-keyring.gpg
        
        # Add Repository
        echo "deb [signed-by=/usr/share/keyrings/windsurf-stable-archive-keyring.gpg arch=amd64] https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt stable main" | sudo tee /etc/apt/sources.list.d/windsurf.list > /dev/null
        
        # Install
        sudo apt-get update -qq
        sudo apt-get install -y windsurf
        echo "✅ Windsurf installed"
    else
        echo "✅ Windsurf already installed"
    fi
    echo ""
fi

# 7. Jupyter Notebook
if [ "$INSTALL_JUPYTER" = true ]; then
    echo "➡️  Installing Jupyter Notebook..."
    if ! command -v jupyter >/dev/null 2>&1; then
        # Install via apt for system-wide stability on Ubuntu 22.04
        sudo apt-get install -y jupyter-notebook python3-pip
        
        echo "✅ Jupyter Notebook installed"
    else
        echo "✅ Jupyter Notebook already installed"
    fi
    echo ""
fi

echo "🎉 Application installation complete!"
