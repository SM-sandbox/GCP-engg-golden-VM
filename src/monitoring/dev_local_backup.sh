#!/bin/bash
#
# Developer Repository Backup Script
# Creates tar.gz backups of all repositories with retention policy
#

set -euo pipefail

# Configuration (can be overridden via environment)
DEV_USER="${DEV_USER:-jerry}"
PROJECTS_ROOT="${PROJECTS_ROOT:-/home/$DEV_USER/projects}"
BACKUPS_DIR="${BACKUPS_DIR:-/var/backups/dev-repos}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
GCS_BUCKET="${GCS_BUCKET:-}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Developer Repository Backup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "User: $DEV_USER"
echo "Source: $PROJECTS_ROOT"
echo "Destination: $BACKUPS_DIR"
echo "Retention: $RETENTION_DAYS days"
if [ ! -z "$GCS_BUCKET" ]; then
    echo "GCS Target: gs://$GCS_BUCKET/$DEV_USER/backups/"
fi
echo ""

# Create backup directory
mkdir -p "$BACKUPS_DIR"

# Get timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DATE=$(date +%Y-%m-%d)

# Create backup for each repository
if [ ! -d "$PROJECTS_ROOT" ]; then
    echo "Projects directory not found: $PROJECTS_ROOT"
    exit 1
fi

BACKUP_COUNT=0
TOTAL_SIZE=0

for repo_dir in "$PROJECTS_ROOT"/*; do
    if [ ! -d "$repo_dir" ]; then
        continue
    fi
    
    REPO_NAME=$(basename "$repo_dir")
    BACKUP_FILE="$BACKUPS_DIR/${DEV_USER}_${REPO_NAME}_${TIMESTAMP}.tar.gz"
    
    echo -n "Backing up $REPO_NAME... "
    
    # Create tar.gz excluding .git directory to save space
    # Include .git if you want full repo backup (larger size)
    tar -czf "$BACKUP_FILE" \
        --exclude="*.pyc" \
        --exclude="__pycache__" \
        --exclude="node_modules" \
        --exclude=".venv" \
        --exclude="venv" \
        --exclude=".env" \
        -C "$PROJECTS_ROOT" \
        "$REPO_NAME" 2>/dev/null
    
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    BACKUP_SIZE_BYTES=$(du -b "$BACKUP_FILE" | cut -f1)
    TOTAL_SIZE=$((TOTAL_SIZE + BACKUP_SIZE_BYTES))
    
    echo -e "${GREEN}✓${NC} ($BACKUP_SIZE)"
    ((BACKUP_COUNT++))
done

echo ""
echo "Backup summary:"
echo "  Repositories backed up: $BACKUP_COUNT"
echo "  Total size: $(numfmt --to=iec-i --suffix=B $TOTAL_SIZE)"
echo ""

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0

find "$BACKUPS_DIR" -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -print0 | while IFS= read -r -d '' file; do
    echo "  Deleting: $(basename "$file")"
    rm -f "$file"
    ((DELETED_COUNT++)) || true
done

if [ $DELETED_COUNT -eq 0 ]; then
    echo "  No old backups to delete"
fi

echo ""
echo -e "${GREEN}✓ Backup complete${NC}"

# Sync to GCS if configured
if [ ! -z "$GCS_BUCKET" ]; then
    echo ""
    echo "Syncing to GCS: gs://$GCS_BUCKET/$DEV_USER/backups/"
    
    if command -v gsutil &> /dev/null; then
        # Create bucket directory if needed (implicit in rsync usually, but safer to check bucket)
        # Sync local backups to GCS (using rsync to mirror deletions)
        gsutil -m rsync -d "$BACKUPS_DIR" "gs://$GCS_BUCKET/$DEV_USER/backups/" 2>&1 | grep -v "^Building synchronization state"
        
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
             echo -e "${GREEN}✓ GCS Sync successful${NC}"
        else
             echo -e "${YELLOW}⚠ GCS Sync warning${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ gsutil not found - skipping GCS sync${NC}"
    fi
fi
