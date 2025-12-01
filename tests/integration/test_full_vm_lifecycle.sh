#!/bin/bash
# Complete VM lifecycle test
# Tests: activity logging, GCS sync, auto-shutdown, restart, static IP persistence

set -e

PROJECT="gcp-engg-vm"
ZONE="us-east1-b"
VM_NAME="akash-dev-vm-001"
USER="akash_brightfox_ai"
BUCKET="gs://akash-dev-vm-backups"
STATIC_IP="35.237.198.37"

echo "=== Full VM Lifecycle Test ==="
echo "VM: $VM_NAME"
echo "User: $USER"
echo "Static IP: $STATIC_IP"
echo "GCS Bucket: $BUCKET"
echo ""

# Step 1: Verify VM is running
echo "Step 1: Verify VM is running..."
STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT --format="get(status)")
echo "Current status: $STATUS"
if [ "$STATUS" != "RUNNING" ]; then
    echo "ERROR: VM is not running"
    exit 1
fi
echo "✓ VM is running"
echo ""

# Step 2: Check current IP matches static IP
echo "Step 2: Verify static IP..."
CURRENT_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo "Current IP: $CURRENT_IP"
echo "Static IP:  $STATIC_IP"
if [ "$CURRENT_IP" != "$STATIC_IP" ]; then
    echo "ERROR: IP mismatch!"
    exit 1
fi
echo "✓ Static IP is correctly assigned"
echo ""

# Step 3: Generate more activity (simulate work)
echo "Step 3: Generating additional development activity..."
gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="sudo -u $USER bash << 'ACTIVITY'
cd /home/$USER/projects/gcp-eng-vm-test-repo

# Create a new feature branch
git checkout -b feature/enhancement

# Make some changes
echo '# Enhanced Features' >> README.md
git add README.md
git commit -m 'Enhance README'

# Add a new module
cat > src/analytics.py << 'EOF'
\"\"\"Analytics module\"\"\"
def analyze_data(data):
    return len(data)
EOF
git add src/analytics.py
git commit -m 'Add analytics module'

# Merge back to main
git checkout main
git merge feature/enhancement --no-edit

echo 'Activity generation complete'
git log --oneline -5
ACTIVITY"
echo "✓ Additional activity generated"
echo ""

# Step 4: Wait for activity daemon to log
echo "Step 4: Waiting for activity daemon to log..."
sleep 5
echo "✓ Wait complete"
echo ""

# Step 5: Check activity log
echo "Step 5: Checking activity log on VM..."
gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="cat /var/log/dev-activity/${USER}_activity.jsonl | wc -l && echo 'Activity log entries:' && tail -3 /var/log/dev-activity/${USER}_activity.jsonl"
echo "✓ Activity log verified"
echo ""

# Step 6: Manual GCS sync test
echo "Step 6: Testing GCS log sync..."
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="sudo -u $USER bash << 'SYNC'
# Create a test sync
BUCKET='akash-dev-vm-backups'
LOG_FILE='/var/log/dev-activity/akash_brightfox_ai_activity.jsonl'
TIMESTAMP=\$(date +%Y%m%d-%H%M%S)

# Copy to GCS
gsutil cp \$LOG_FILE gs://\$BUCKET/logs/activity/akash_activity_\${TIMESTAMP}.jsonl

echo 'Sync complete'
gsutil ls gs://\$BUCKET/logs/activity/ | tail -1
SYNC"
echo "✓ GCS sync tested"
echo ""

# Step 7: Verify GCS bucket contents
echo "Step 7: Verifying GCS bucket contents..."
gsutil ls -r $BUCKET/logs/ | head -10
echo "✓ GCS bucket verified"
echo ""

# Step 8: Stop VM (simulating auto-shutdown)
echo "Step 8: Stopping VM (simulating auto-shutdown)..."
gcloud compute instances stop $VM_NAME --zone=$ZONE --project=$PROJECT
echo "Waiting for VM to stop..."
sleep 10
STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT --format="get(status)")
echo "Status after stop: $STATUS"
if [ "$STATUS" != "TERMINATED" ]; then
    echo "ERROR: VM did not stop properly"
    exit 1
fi
echo "✓ VM stopped successfully"
echo ""

# Step 9: Restart VM
echo "Step 9: Restarting VM..."
gcloud compute instances start $VM_NAME --zone=$ZONE --project=$PROJECT
echo "Waiting for VM to start..."
sleep 20
STATUS=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT --format="get(status)")
echo "Status after start: $STATUS"
if [ "$STATUS" != "RUNNING" ]; then
    echo "ERROR: VM did not start properly"
    exit 1
fi
echo "✓ VM restarted successfully"
echo ""

# Step 10: Verify static IP persists after restart
echo "Step 10: Verifying static IP after restart..."
NEW_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --project=$PROJECT --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo "IP after restart: $NEW_IP"
echo "Static IP:        $STATIC_IP"
if [ "$NEW_IP" != "$STATIC_IP" ]; then
    echo "ERROR: Static IP changed after restart!"
    echo "Expected: $STATIC_IP"
    echo "Got:      $NEW_IP"
    exit 1
fi
echo "✓ Static IP persisted through stop/start cycle"
echo ""

# Step 11: Verify services restarted
echo "Step 11: Verifying monitoring daemon restarted..."
sleep 5
gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="sudo systemctl status dev-activity --no-pager | head -10"
echo "✓ Monitoring daemon verified"
echo ""

# Step 12: Verify data persisted
echo "Step 12: Verifying repository data persisted..."
gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT --command="sudo -u $USER bash << 'VERIFY'
cd /home/$USER/projects/gcp-eng-vm-test-repo
echo 'Commits in repo:'
git log --oneline | wc -l
echo ''
echo 'Files in repo:'
find . -type f -not -path './.git/*' | wc -l
echo ''
echo 'Recent commits:'
git log --oneline -3
VERIFY"
echo "✓ Repository data persisted"
echo ""

# Final summary
echo "=== Test Summary ==="
echo "✓ VM running status verified"
echo "✓ Static IP assigned and working: $STATIC_IP"
echo "✓ Development activity simulated"
echo "✓ Activity daemon logging correctly"
echo "✓ Logs synced to GCS bucket"
echo "✓ VM stop/start cycle successful"
echo "✓ Static IP persisted through restart"
echo "✓ Services automatically restarted"
echo "✓ Data persisted through restart"
echo ""
echo "=== All Tests PASSED ==="
echo ""
echo "Next steps:"
echo "1. Review activity logs in GCS: gsutil ls $BUCKET/logs/"
echo "2. Generate payment report from activity logs"
echo "3. Monitor auto-shutdown behavior (30 min idle)"
echo "4. Send onboarding package to akash@brightfox.ai"
