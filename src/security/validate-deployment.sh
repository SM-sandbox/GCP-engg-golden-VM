#!/bin/bash
set -e

# VM Validation Suite
# Runs on the VM to verify everything is configured correctly.

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "🧪 VM VALIDATION SUITE"
echo "=================================================="
echo "Running on: $(hostname)"
echo "User: $(whoami)"
echo ""

FAILURES=0

check() {
    DESC=$1
    CMD=$2
    if eval "$CMD" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS:${NC} $DESC"
    else
        echo -e "${RED}❌ FAIL:${NC} $DESC"
        FAILURES=$((FAILURES + 1))
    fi
}

check_app() {
    APP_NAME=$1
    CMD=$2
    if eval "$CMD" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS:${NC} $APP_NAME installed"
    else
        echo -e "${RED}❌ FAIL:${NC} $APP_NAME NOT installed"
        FAILURES=$((FAILURES + 1))
    fi
}

# 1. Security Checks
echo "--- Security ---"
# We expect sudo -n true to FAIL (return code != 0)
if sudo -n true 2>/dev/null; then
    echo -e "${RED}❌ FAIL:${NC} User has passwordless sudo access! (BAD)"
    FAILURES=$((FAILURES + 1))
else
    echo -e "${GREEN}✅ PASS:${NC} User denied passwordless sudo (GOOD)"
fi

# 2. Application Checks
echo "--- Applications ---"
echo "➡️  Checking Applications..."
check_app "Google Chrome" "google-chrome --version"
check_app "Windsurf" "windsurf --help"
check_app "Jupyter" "jupyter --version"
check_app "Python" "python3 --version"
check_app "Node.js" "node --version"
check_app "Git" "git --version"
check_app "GitHub CLI" "gh --version"
check_app "Azure CLI" "az --version"
check_app "Azure Dev CLI" "azd version"
echo ""

# 3. Monitoring Tools
echo "--- Monitoring Dependencies ---"
check "xprintidle installed" "command -v xprintidle >/dev/null"
check "wmctrl installed" "command -v wmctrl >/dev/null"
check "scrot installed" "command -v scrot >/dev/null"

# 4. Service Status
echo "--- Services ---"
check "Activity Daemon Active" "systemctl is-active dev-activity >/dev/null"
# Security: Service file must be owned by root and not writable by others
if [ -f /etc/systemd/system/dev-activity.service ]; then
    OWNER=$(stat -c '%U' /etc/systemd/system/dev-activity.service)
    PERMS=$(stat -c '%a' /etc/systemd/system/dev-activity.service)
    if [ "$OWNER" == "root" ]; then
        echo -e "${GREEN}✅ PASS:${NC} Service file owned by root"
    else
        echo -e "${RED}❌ FAIL:${NC} Service file owned by $OWNER (Should be root)"
        FAILURES=$((FAILURES + 1))
    fi
fi

# 5. Logging & Data Configuration
echo "--- Logging ---"
check "Activity Log Dir exists" "[ -d /var/log/dev-activity ]"
check "Git Log Dir exists" "[ -d /var/log/dev-git ]"
check "Backups Dir exists" "[ -d /var/backups/dev-repos ]"
# Check root ownership of monitoring scripts
if [ -d /opt/dev-monitoring ]; then
    OWNER=$(stat -c '%U' /opt/dev-monitoring/dev_activity_daemon.py)
    if [ "$OWNER" == "root" ]; then
        echo -e "${GREEN}✅ PASS:${NC} Monitoring scripts owned by root"
    else
        echo -e "${RED}❌ FAIL:${NC} Monitoring scripts owned by $OWNER (Should be root)"
        FAILURES=$((FAILURES + 1))
    fi
fi

# 6. Cron Jobs
echo "--- Cron ---"
check "Git Stats Cron" "[ -f /etc/cron.d/dev-git-stats ]"
check "Backup Cron" "[ -f /etc/cron.d/dev-backup ]"

# 7. Static IP Verification (Optional Arg)
EXPECTED_IP=$1
if [ ! -z "$EXPECTED_IP" ]; then
    echo "--- Networking ---"
    CURRENT_IP=$(hostname -I | awk '{print $1}') # Internal IP
    # External IP check requires curl
    EXTERNAL_IP=$(curl -s -m 2 http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")
    
    if [ "$EXTERNAL_IP" == "$EXPECTED_IP" ]; then
        echo -e "${GREEN}✅ PASS:${NC} Static IP matches ($EXTERNAL_IP)"
    else
        echo -e "${RED}❌ FAIL:${NC} IP Mismatch. Expected $EXPECTED_IP, got $EXTERNAL_IP"
        FAILURES=$((FAILURES + 1))
    fi
fi

echo ""
echo "=================================================="
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}💀 $FAILURES TESTS FAILED${NC}"
    exit 1
fi
