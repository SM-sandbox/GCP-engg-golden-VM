#!/bin/bash
#
# GCS Log Sync Script
# Syncs activity and git logs to Google Cloud Storage with per-engineer directory structure
#

set -euo pipefail

# Configuration
DEV_USER="${DEV_USER:-jerry}"
ACTIVITY_LOG_DIR="${ACTIVITY_LOG_DIR:-/var/log/dev-activity}"
GIT_LOG_DIR="${GIT_LOG_DIR:-/var/log/dev-git}"
GCS_BUCKET="${GCS_BUCKET:-}"
RETENTION_DAYS="${RETENTION_DAYS:-180}"  # 6 months (180 days) for billing/payroll

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$GCS_BUCKET" ]; then
    echo -e "${RED}Error: GCS_BUCKET not set${NC}"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GCS Log Sync - Per-Engineer Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Engineer: $DEV_USER"
echo "Bucket: gs://$GCS_BUCKET"
echo "Structure: gs://$GCS_BUCKET/$DEV_USER/{activity,git}/"
echo "Retention: $RETENTION_DAYS days (6 months)"
echo ""

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    echo -e "${RED}Error: gsutil not found${NC}"
    exit 1
fi

# Verify bucket exists or create it
if ! gsutil ls "gs://$GCS_BUCKET" &>/dev/null; then
    echo "Creating bucket: gs://$GCS_BUCKET"
    gsutil mb -c standard -l us-east1 "gs://$GCS_BUCKET" || {
        echo -e "${RED}Error: Failed to create bucket${NC}"
        exit 1
    }
    echo -e "${GREEN}✓${NC} Bucket created"
fi

# Sync activity logs to engineer-specific directory
if [ -d "$ACTIVITY_LOG_DIR" ]; then
    echo "Syncing activity logs..."
    echo "  Source: $ACTIVITY_LOG_DIR"
    echo "  Destination: gs://$GCS_BUCKET/$DEV_USER/activity/"
    
    gsutil -m rsync -r -d "$ACTIVITY_LOG_DIR" "gs://$GCS_BUCKET/$DEV_USER/activity/" 2>&1 | grep -v "^Building synchronization state"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        FILE_COUNT=$(gsutil ls "gs://$GCS_BUCKET/$DEV_USER/activity/" | wc -l)
        echo -e "  ${GREEN}✓${NC} Activity logs synced ($FILE_COUNT files)"
    else
        echo -e "  ${YELLOW}⚠${NC} Activity logs sync had warnings"
    fi
fi

# Sync git logs to engineer-specific directory
if [ -d "$GIT_LOG_DIR" ]; then
    echo "Syncing git logs..."
    echo "  Source: $GIT_LOG_DIR"
    echo "  Destination: gs://$GCS_BUCKET/$DEV_USER/git/"
    
    gsutil -m rsync -r -d "$GIT_LOG_DIR" "gs://$GCS_BUCKET/$DEV_USER/git/" 2>&1 | grep -v "^Building synchronization state"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        FILE_COUNT=$(gsutil ls "gs://$GCS_BUCKET/$DEV_USER/git/" | wc -l)
        echo -e "  ${GREEN}✓${NC} Git logs synced ($FILE_COUNT files)"
    else
        echo -e "  ${YELLOW}⚠${NC} Git logs sync had warnings"
    fi
fi

# Set lifecycle policy for automatic deletion (6 months)
LIFECYCLE_CONFIG=$(mktemp)
cat > "$LIFECYCLE_CONFIG" << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": $RETENTION_DAYS
        }
      }
    ]
  }
}
EOF

echo ""
echo "Setting lifecycle policy..."
echo "  Retention: ${RETENTION_DAYS} days (6 months)"
echo "  Applies to: All files in bucket"

gsutil lifecycle set "$LIFECYCLE_CONFIG" "gs://$GCS_BUCKET" 2>&1 | grep -v "^Setting lifecycle"
rm "$LIFECYCLE_CONFIG"

echo -e "  ${GREEN}✓${NC} Lifecycle policy updated"

# Display bucket structure
echo ""
echo "Bucket structure:"
gsutil ls "gs://$GCS_BUCKET/$DEV_USER/" 2>/dev/null || echo "  gs://$GCS_BUCKET/$DEV_USER/ (empty or first sync)"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Sync complete for $DEV_USER${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Access logs:"
echo "  gsutil ls gs://$GCS_BUCKET/$DEV_USER/activity/"
echo "  gsutil ls gs://$GCS_BUCKET/$DEV_USER/git/"
echo ""
