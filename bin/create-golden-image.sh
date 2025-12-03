#!/bin/bash
#
# Create or update the golden image
# Usage: ./create-golden-image.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Creating Golden Image"
echo "====================="
echo ""

# Use the create-gnome-image script
"$REPO_ROOT/src/golden-image/create-gnome-image.sh" "$@"
