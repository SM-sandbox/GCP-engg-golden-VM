#!/bin/bash
#
# Cleanup unused GCP resources (VMs, IPs, disks)
# Usage: ./cleanup-resources.sh [--dry-run]
#
set -euo pipefail

PROJECT="gcp-engg-vm"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE - No changes will be made"
    echo ""
fi

echo "GCP Resource Cleanup"
echo "===================="
echo "Project: $PROJECT"
echo ""

# List terminated VMs
echo "--- Terminated VMs ---"
gcloud compute instances list --project=$PROJECT --filter="status=TERMINATED" --format="table(name,zone,status)"

# List unused static IPs
echo ""
echo "--- Unused Static IPs (costing \$0.01/hr each) ---"
gcloud compute addresses list --project=$PROJECT --filter="status=RESERVED" --format="table(name,address,status)"

# List orphaned disks
echo ""
echo "--- Orphaned Disks ---"
gcloud compute disks list --project=$PROJECT --filter="NOT users:*" --format="table(name,zone,sizeGb,status)"

if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    echo "To delete these resources, run the appropriate gcloud commands."
    echo "Or run with --dry-run to see what would be cleaned up."
fi
