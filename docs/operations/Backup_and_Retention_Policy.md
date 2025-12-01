# Backup and Retention Policy

## Overview

Multi-layered backup strategy ensuring data protection while managing storage costs.

## Backup Layers

### Layer 1: Local VM Backups

**Location:** `/var/backups/dev-repos/`

**What:** Tar.gz archives of all repositories

**Schedule:** Daily at 2:00 AM

**Retention:** 7 days (configurable)

**Storage:** Local VM disk

**Excludes:**
- `.git/` directory (optional)
- `node_modules/`
- `__pycache__/`
- `.venv/`, `venv/`
- `.env` files
- Compiled binaries

**Advantages:**
- Fast restore
- No network dependency
- Automated via cron

**Disadvantages:**
- Lost if VM deleted
- Consumes local disk space
- Not accessible from other locations

### Layer 2: GCS Cloud Backups

**Location:** `gs://<dev-user>-dev-vm-backups/logs/`

**What:** Activity logs + Git statistics logs

**Schedule:** Daily at 3:00 AM

**Retention:** 30 days (lifecycle policy)

**Storage:** Google Cloud Storage (Standard class)

**Synced directories:**
- `/var/log/dev-activity/` → `gs://bucket/logs/activity/`
- `/var/log/dev-git/` → `gs://bucket/logs/git/`

**Advantages:**
- Survives VM deletion
- Accessible from anywhere
- Automatic lifecycle management
- Low cost for logs

**Disadvantages:**
- Requires network connectivity
- Doesn't include repository contents
- Monthly GCS storage costs

### Layer 3: GCP Disk Snapshots (Manual)

**Location:** GCP Compute Engine Snapshots

**What:** Complete VM disk image

**Schedule:** Manual (on-demand)

**Retention:** Indefinite (manual cleanup)

**Use cases:**
- Before major changes
- VM migration
- Long-term archival
- Developer offboarding

**Command:**
```bash
gcloud compute disks snapshot <vm-name> \
  --snapshot-names=<vm-name>-<date> \
  --zone=<zone>
```

**Restore:**
```bash
gcloud compute disks create <new-disk> \
  --source-snapshot=<snapshot-name> \
  --zone=<zone>
```

## Data Recovery Scenarios

### Scenario 1: Accidental File Deletion (< 7 days)

**Recovery:** Local backup restore

```bash
# SSH into VM
gcloud compute ssh <vm-name> --zone=<zone>

# List available backups
ls -lh /var/backups/dev-repos/

# Extract specific repository
cd ~/projects/
tar -xzf /var/backups/dev-repos/repo-name_YYYYMMDD-HHMMSS.tar.gz

# Verify contents
ls -la repo-name/
```

**Recovery Time:** < 5 minutes

### Scenario 2: VM Accidental Deletion (Logs only)

**Recovery:** GCS restore

```bash
# From local machine
gsutil -m cp -r gs://<bucket>/logs/ ./recovered-logs/

# Analyze with reporting tool
python3 reporting/aggregate_dev_logs.py \
  --dev-user <user> \
  --month <YYYY-MM> \
  --activity-log-dir ./recovered-logs/activity \
  --git-log-dir ./recovered-logs/git
```

**Recovery Time:** < 30 minutes (depending on log size)

**Note:** Repository contents NOT recoverable from GCS (only logs)

### Scenario 3: VM Accidental Deletion (Full Restore)

**Recovery:** Disk snapshot restore

```bash
# Create new VM from snapshot
gcloud compute instances create <vm-name>-restored \
  --zone=<zone> \
  --machine-type=<type> \
  --create-disk=name=<disk-name>,boot=yes,source-snapshot=<snapshot-name>

# Start VM
gcloud compute instances start <vm-name>-restored --zone=<zone>
```

**Recovery Time:** 10-30 minutes

**Requires:** Prior disk snapshot creation

### Scenario 4: Corrupted Repository (> 7 days ago)

**Recovery Options:**

1. **Git History:** Use git reflog/reset if commits preserved
2. **GitHub Remote:** Re-clone from GitHub (if pushed)
3. **Disk Snapshot:** If snapshot exists from that timeframe
4. **Lost:** If none of the above available

**Prevention:** Regular git pushes to remote

## Retention Policies

### Local Backups

```bash
# Configured in cron job
RETENTION_DAYS=7

# Automated cleanup
find /var/backups/dev-repos/ -name "*.tar.gz" -mtime +7 -delete
```

**Adjust retention:**
```bash
# Edit cron job
sudo vi /etc/cron.d/dev-backup

# Change RETENTION_DAYS=7 to desired value
```

### GCS Lifecycle Policy

Automatically applied on sync:

```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 30,
          "matchesPrefix": ["logs/"]
        }
      }
    ]
  }
}
```

**Adjust retention:**
```bash
# Edit sync script
sudo vi /opt/dev-monitoring/sync_dev_logs_to_gcs.sh

# Change RETENTION_DAYS=30 to desired value
```

## Storage Capacity Planning

### Local Backup Storage

**Per repository:** 10-500 MB compressed

**Example calculation:**
- 5 repositories × 200 MB avg × 7 days = ~7 GB
- Add 50% buffer = ~10 GB

**Monitoring:**
```bash
# Check backup directory size
du -sh /var/backups/dev-repos/

# Check available space
df -h /var/backups/
```

**If running low:**
1. Reduce retention days
2. Exclude more directories
3. Increase VM disk size

### GCS Storage

**Per developer per month:** 1-10 GB (logs only)

**Cost estimate (us-east1):**
- Storage: $0.020 per GB/month
- 5 GB × $0.020 = $0.10/month per developer
- Network egress: Minimal (logs only)

**Monitoring:**
```bash
# Check bucket size
gsutil du -sh gs://<bucket-name>/

# Check costs
gcloud billing accounts list
```

## Backup Verification

### Monthly Verification Checklist

```bash
# 1. Verify local backups exist
gcloud compute ssh <vm> --command="ls -lh /var/backups/dev-repos/ | tail -10"

# 2. Verify GCS sync working
gsutil ls -lh gs://<bucket>/logs/activity/ | tail -5

# 3. Test restore (non-destructive)
gcloud compute ssh <vm> --command="
  mkdir -p /tmp/restore-test
  cd /tmp/restore-test
  tar -xzf /var/backups/dev-repos/*latest*.tar.gz
  ls -la
  rm -rf /tmp/restore-test
"

# 4. Verify cron jobs running
gcloud compute ssh <vm> --command="
  sudo systemctl status cron
  grep -i backup /var/log/syslog | tail -5
"
```

## Disaster Recovery Procedure

### Complete VM Loss

**Required information:**
- Developer username
- GCP project ID
- Last known VM configuration

**Steps:**

1. **Create new VM:**
   ```bash
   ./bootstrap/bootstrap_dev_vm.sh config/users/<user>.yaml
   ```

2. **Restore configuration:**
   ```bash
   ./bootstrap/ensure_env_from_config.sh config/users/<user>.yaml
   ```

3. **Recover logs from GCS:**
   ```bash
   gsutil -m rsync -r \
     gs://<bucket>/logs/activity/ \
     /var/log/dev-activity/
   
   gsutil -m rsync -r \
     gs://<bucket>/logs/git/ \
     /var/log/dev-git/
   ```

4. **Re-clone repositories:**
   ```bash
   # Repositories will be empty - developer must re-clone
   # Or restore from disk snapshot if available
   ```

5. **Resume monitoring:**
   ```bash
   ./vm-scripts/install_monitoring.sh config/users/<user>.yaml
   ```

**Data Loss:**
- Repository changes not pushed to GitHub
- Activity data older than GCS retention
- VM-specific configurations not in YAML

**Recovery Time:** 30-60 minutes

## Backup Best Practices

### For Developers

1. **Push regularly:** Commit and push to GitHub daily
2. **Use branches:** Work on feature branches
3. **Tag releases:** Create git tags for important milestones
4. **Document locally:** Keep important notes in git-tracked files
5. **Report issues:** Alert admin if backups seem to fail

### For Administrators

1. **Monitor backup jobs:** Check logs weekly
2. **Test restores:** Monthly restore verification
3. **Review retention:** Adjust based on usage patterns
4. **Create snapshots:** Before major VM changes
5. **Document procedures:** Keep this guide updated

### Pre-VM Deletion Checklist

Before deleting a VM:

- [ ] Create final disk snapshot
- [ ] Generate final month-end report
- [ ] Verify all code pushed to GitHub
- [ ] Download GCS logs locally
- [ ] Archive important documentation
- [ ] Export any VM-specific configurations
- [ ] Notify developer

## Cost Optimization

### Reducing Backup Costs

1. **Adjust retention:**
   - Local: 5 days instead of 7
   - GCS: 14 days instead of 30

2. **Exclude more:**
   - Skip `.git` directories (reduce by 50-70%)
   - Exclude test data
   - Exclude build artifacts

3. **Compress better:**
   - Use `tar -czf` with maximum compression
   - Trade CPU time for storage savings

4. **Selective backups:**
   - Only backup actively developed repos
   - Skip archived/read-only repositories

### Storage Class Options

**Standard (default):** Best for frequently accessed logs

**Nearline:** $0.010/GB/month (30-day minimum)
- Good for logs older than 30 days
- Use lifecycle policy to transition

**Coldline:** $0.004/GB/month (90-day minimum)
- Good for long-term archival
- Higher retrieval costs

## Compliance Considerations

- **Data Residency:** All data in `us-east1` region
- **Access Control:** IAM policies on GCS buckets
- **Encryption:** At-rest encryption by default
- **Audit Logs:** Cloud Audit Logs for GCS access
- **Retention:** Configurable to meet compliance requirements

## Support

For backup/restore issues:
- Check monitoring logs
- Review this document
- Contact: scott@brightfox.ai
