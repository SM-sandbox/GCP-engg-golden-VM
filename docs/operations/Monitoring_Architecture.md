# Monitoring Architecture

## Overview

The monitoring system tracks developer activity, git statistics, and automates backups across all developer VMs.

## Components

### 1. Activity Daemon (`dev_activity_daemon.py`)

**Purpose:** Real-time monitoring of developer activity and idle detection

**Runs as:** Systemd service (root)

**Check Interval:** 60 seconds (configurable)

**Tracks:**
- File modifications in `~/projects/`
- CPU usage percentage
- Active user processes
- SSH session count
- Process names and CPU utilization

**Auto-Shutdown Logic:**
- Monitors for idle state (no file changes, low CPU, no SSH)
- Triggers shutdown after 30 minutes of continuous inactivity
- Prevents runaway costs from forgotten VMs

**Logs:** `/var/log/dev-activity/<user>_activity.jsonl`

**Log Format:**
```json
{
  "timestamp": "2024-11-21T15:30:00Z",
  "user": "jerry",
  "event_type": "activity_detected",
  "details": {
    "cpu_usage": 12.5,
    "process_count": 8,
    "modified_files": 3,
    "files": ["repo1/main.py", "repo2/test.js"],
    "ssh_sessions": 1,
    "active_processes": ["python3", "node"]
  }
}
```

**Management:**
```bash
# Status
systemctl status dev-activity

# Logs
journalctl -u dev-activity -f

# Restart
systemctl restart dev-activity

# Disable auto-shutdown temporarily
systemctl stop dev-activity
```

### 2. Git Statistics Collector (`dev_git_stats.py`)

**Purpose:** Track lines of code, commits, and repository activity

**Runs as:** Cron job (developer user)

**Schedule:** Hourly

**Collects per repository:**
- Total commits
- Commits in last 24 hours
- LOC changes (insertions/deletions)
- Files changed
- Current branch
- Uncommitted changes (staged/unstaged/untracked)
- Last commit details
- Top contributors

**Logs:** 
- Daily: `/var/log/dev-git/<user>_git_stats_YYYY-MM-DD.jsonl`
- Latest: `/var/log/dev-git/<user>_git_stats_latest.json`

**Log Format:**
```json
{
  "timestamp": "2024-11-21T16:00:00Z",
  "repository": "gcp-eng-vm-test-repo",
  "path": "/home/jerry/projects/gcp-eng-vm-test-repo",
  "current_branch": "main",
  "total_commits": 142,
  "commits_last_24h": 5,
  "loc_changes_24h": {
    "insertions": 234,
    "deletions": 67,
    "files_changed": 8
  },
  "files_changed_24h": 8,
  "unstaged_files": 2,
  "staged_files": 0,
  "untracked_files": 1
}
```

**Manual Run:**
```bash
python3 /opt/dev-monitoring/dev_git_stats.py
```

### 3. Local Backup (`dev_local_backup.sh`)

**Purpose:** Daily snapshots of all repositories

**Runs as:** Cron job (root)

**Schedule:** Daily at 2:00 AM

**Process:**
- Creates tar.gz archives of each repository
- Excludes: `.git/`, `node_modules/`, `__pycache__/`, `.venv/`
- Names: `<repo>_YYYYMMDD-HHMMSS.tar.gz`
- Location: `/var/backups/dev-repos/`
- Retention: 7 days (configurable)

**Backup Format:**
```
/var/backups/dev-repos/
├── gcp-eng-vm-test-repo_20241121-020001.tar.gz
├── internal-pipeline_20241121-020002.tar.gz
└── monitoring-tools_20241121-020003.tar.gz
```

**Manual Backup:**
```bash
sudo bash /opt/dev-monitoring/dev_local_backup.sh
```

**Restore:**
```bash
cd /home/jerry/projects/
tar -xzf /var/backups/dev-repos/repo_20241121-020001.tar.gz
```

### 4. GCS Sync (`sync_dev_logs_to_gcs.sh`)

**Purpose:** Cloud backup of logs to Google Cloud Storage

**Runs as:** Cron job (root)

**Schedule:** Daily at 3:00 AM

**Syncs:**
- Activity logs → `gs://<bucket>/logs/activity/`
- Git logs → `gs://<bucket>/logs/git/`

**Features:**
- Automatic bucket creation if missing
- Lifecycle policy: auto-delete after 30 days
- Incremental sync (only changed files)

**Manual Sync:**
```bash
sudo GCS_BUCKET=<bucket-name> bash /opt/dev-monitoring/sync_dev_logs_to_gcs.sh
```

**View Cloud Logs:**
```bash
gsutil ls -r gs://<bucket-name>/logs/
```

## Data Flow

```
Developer Activity
       ↓
  Activity Daemon (60s intervals)
       ↓
  /var/log/dev-activity/
       ↓
  GCS Sync (daily)
       ↓
  gs://bucket/logs/activity/
       ↓
  Month-End Aggregation
       ↓
  CSV Report
```

```
Git Repositories
       ↓
  Git Stats Collector (hourly)
       ↓
  /var/log/dev-git/
       ↓
  GCS Sync (daily)
       ↓
  gs://bucket/logs/git/
       ↓
  Month-End Aggregation
       ↓
  CSV Report
```

## Cron Schedule

All cron jobs defined in `/etc/cron.d/`:

```
# Git Statistics - Hourly
0 * * * * jerry python3 /opt/dev-monitoring/dev_git_stats.py

# Local Backup - Daily 2 AM
0 2 * * * root bash /opt/dev-monitoring/dev_local_backup.sh

# GCS Sync - Daily 3 AM
0 3 * * * root bash /opt/dev-monitoring/sync_dev_logs_to_gcs.sh
```

View cron logs:
```bash
grep CRON /var/log/syslog
tail -f /var/log/dev-git/cron.log
tail -f /var/log/dev-activity/backup.log
tail -f /var/log/dev-activity/gcs-sync.log
```

## Systemd Services

### dev-activity.service

Location: `/etc/systemd/system/dev-activity.service`

```ini
[Unit]
Description=Developer Activity Monitoring Daemon
After=network.target

[Service]
Type=simple
User=root
Environment="DEV_USER=jerry"
Environment="PROJECTS_ROOT=/home/jerry/projects"
Environment="ACTIVITY_LOG_DIR=/var/log/dev-activity"
ExecStart=/usr/bin/python3 /opt/dev-monitoring/dev_activity_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Performance Impact

- **Activity Daemon:** Minimal (<1% CPU, ~20MB RAM)
- **Git Stats (hourly):** Brief spike (~2-5 seconds)
- **Backup (daily):** Moderate I/O, depends on repo size
- **GCS Sync (daily):** Network bandwidth usage

## Security Considerations

1. **Log Access:**
   - Activity logs: Root and developer can read
   - Git logs: Developer owns
   - Backups: Root only

2. **Shutdown Permissions:**
   - Special sudoers rule allows shutdown
   - File: `/etc/sudoers.d/dev-shutdown`

3. **GCS Access:**
   - Uses VM service account
   - Requires `storage.admin` scope

4. **Sensitive Data:**
   - Logs contain file names and paths
   - No file contents stored
   - Commit messages included in git logs

## Troubleshooting

### Activity Daemon Stopped

```bash
# Check status
systemctl status dev-activity

# View logs
journalctl -u dev-activity -n 100 --no-pager

# Common issues:
# - Python dependencies missing: sudo pip3 install psutil
# - Permission errors: Check /var/log/dev-activity/ ownership
# - Projects directory missing: Create ~/projects/
```

### Git Stats Not Running

```bash
# Check cron job
cat /etc/cron.d/dev-git-stats

# Check logs
tail -f /var/log/dev-git/cron.log

# Run manually
sudo -u jerry python3 /opt/dev-monitoring/dev_git_stats.py

# Common issues:
# - Not a git repo: Verify ~/projects/ contains git repositories
# - Permission denied: Check directory ownership
```

### Backup Failed

```bash
# Check logs
tail -f /var/log/dev-activity/backup.log

# Check disk space
df -h /var/backups/

# Common issues:
# - Disk full: Adjust retention policy or increase disk size
# - Permission denied: Backup runs as root
```

### GCS Sync Failed

```bash
# Check logs
tail -f /var/log/dev-activity/gcs-sync.log

# Verify bucket
gsutil ls gs://<bucket-name>

# Test credentials
gcloud auth list

# Common issues:
# - Bucket doesn't exist: Created automatically on first run
# - Permission denied: Check service account scopes
# - Network error: Verify VM can reach GCS
```

## Monitoring Metrics

Key metrics to track:

1. **Activity Events/Day:** Should correlate with work days
2. **Idle Shutdowns:** Frequent = good (cost optimization)
3. **LOC Changes:** Productivity indicator
4. **Commit Frequency:** Development velocity
5. **Backup Success Rate:** Should be 100%
6. **GCS Sync Lag:** Should be < 24 hours

## Future Enhancements

- Real-time alerting (Slack/email on events)
- Dashboard UI for viewing metrics
- Anomaly detection (unusual activity patterns)
- Resource usage tracking (memory, disk)
- Integration with external monitoring (Datadog, New Relic)
