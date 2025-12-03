#!/bin/bash
#
# Provision a new user VM from golden image
# Usage: ./provision-user.sh <user-config.yaml>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <user-config.yaml>"
    echo "Example: $0 config/users/akash.yaml"
    exit 1
fi

CONFIG_FILE="$1"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "Provisioning user VM from config: $CONFIG_FILE"
echo ""

# Use the clone-vm-from-image script
"$REPO_ROOT/src/provisioning/clone-vm-from-image.sh" "$CONFIG_FILE"
