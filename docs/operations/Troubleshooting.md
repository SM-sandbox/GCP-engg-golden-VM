# Troubleshooting Guide

## Common Issues and Solutions

### VM Creation & Bootstrap

#### Issue: VM creation fails with quota exceeded

**Symptoms:**
```
ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - Quota 'CPUS' exceeded. Limit: 24.0 in region us-east1.
```

**Solution:**
```bash
# Check current quota
gcloud compute project-info describe --project=<project-id>

# Request quota increase
# Go to: https://console.cloud.google.com/iam-admin/quotas

# Or use smaller machine type
# Edit config: machine_type: n1-standard-2
```

#### Issue: SSH connection fails after VM creation

**Symptoms:**
```
ERROR: (gcloud.compute.ssh) Could not SSH into the instance.
```

**Solutions:**
1. Wait 30-60 seconds for VM to fully boot
2. Check firewall rules:
   ```bash
   gcloud compute firewall-rules list --project=<project-id>
   ```
3. Verify VM is running:
   ```bash
   gcloud compute instances describe <vm-name> --zone=<zone>
   ```
4. Check SSH keys:
   ```bash
   gcloud compute os-login describe-profile
   ```

#### Issue: Deploy key registration fails

**Symptoms:**
```
HTTP 422: Validation Failed (key is already in use)
```

**Solution:**
```bash
# List existing deploy keys
gh repo deploy-key list --repo <org/repo>

# Delete conflicting key
gh repo deploy-key delete <key-id> --repo <org/repo>

# Re-add
gh repo deploy-key add .keys/<user>_<vm>.pub --repo <org/repo>
```

### Environment Provisioning

#### Issue: Package installation fails

**Symptoms:**
```
E: Unable to locate package <package-name>
```

**Solutions:**
1. Update package lists:
   ```bash
   sudo apt-get update
   ```
2. Check package name spelling
3. Check Ubuntu version compatibility

#### Issue: Cloud SDK installation fails

**Symptoms:**
```
curl: (6) Could not resolve host: sdk.cloud.google.com
```

**Solutions:**
1. Check network connectivity:
   ```bash
   ping google.com
   ```
2. Check DNS resolution:
   ```bash
   cat /etc/resolv.conf
   ```
3. Verify firewall rules allow outbound HTTPS

#### Issue: Python venv creation fails

**Symptoms:**
```
Error: The virtual environment was not created successfully
```

**Solutions:**
```bash
# Install python3-venv
sudo apt-get install -y python3-venv python3-pip

# Clear previous attempt
rm -rf ~/envs/jupyter-env

# Retry creation
python3 -m venv ~/envs/jupyter-env
```

### Monitoring & Automation

#### Issue: Activity daemon not running

**Check status:**
```bash
systemctl status dev-activity
```

**Common causes:**

1. **Python dependencies missing:**
   ```bash
   sudo pip3 install psutil
   sudo systemctl restart dev-activity
   ```

2. **Permission errors:**
   ```bash
   sudo mkdir -p /var/log/dev-activity
   sudo chown -R <user>:<user> /var/log/dev-activity
   sudo systemctl restart dev-activity
   ```

3. **Configuration errors:**
   ```bash
   # Check service file
   cat /etc/systemd/system/dev-activity.service
   
   # View detailed logs
   journalctl -u dev-activity -n 100 --no-pager
   ```

#### Issue: Git stats not collecting

**Check cron job:**
```bash
cat /etc/cron.d/dev-git-stats
```

**Check logs:**
```bash
tail -f /var/log/dev-git/cron.log
```

**Common causes:**

1. **Not a git repository:**
   ```bash
   cd ~/projects/<repo>
   git status
   ```

2. **Permission denied:**
   ```bash
   ls -la ~/projects/
   # Should be owned by developer user
   ```

3. **Script errors:**
   ```bash
   # Run manually to see errors
   python3 /opt/dev-monitoring/dev_git_stats.py
   ```

#### Issue: Backups not running

**Check cron job:**
```bash
cat /etc/cron.d/dev-backup
```

**Check logs:**
```bash
tail -f /var/log/dev-activity/backup.log
```

**Common causes:**

1. **Disk full:**
   ```bash
   df -h /var/backups/
   
   # Clean old backups manually
   sudo find /var/backups/dev-repos/ -name "*.tar.gz" -mtime +7 -delete
   ```

2. **Permission errors:**
   ```bash
   sudo mkdir -p /var/backups/dev-repos
   sudo chmod 755 /var/backups/dev-repos
   ```

3. **Source directory missing:**
   ```bash
   ls -la ~/projects/
   ```

#### Issue: GCS sync fails

**Check logs:**
```bash
tail -f /var/log/dev-activity/gcs-sync.log
```

**Common causes:**

1. **Bucket doesn't exist:**
   ```bash
   gsutil ls gs://<bucket-name>
   
   # Create if missing
   gsutil mb -c standard -l us-east1 gs://<bucket-name>
   ```

2. **Permission denied:**
   ```bash
   # Check service account
   gcloud auth list
   
   # Verify scopes
   gcloud compute instances describe <vm-name> --zone=<zone> \
     --format='get(serviceAccounts[].scopes)'
   ```

3. **Network issues:**
   ```bash
   # Test connectivity
   curl -I https://storage.googleapis.com
   
   # Test gsutil
   gsutil ls
   ```

### Repository Access

#### Issue: Cannot clone repository

**Symptoms:**
```
git@github.com: Permission denied (publickey).
fatal: Could not read from remote repository.
```

**Solutions:**

1. **Verify deploy key added:**
   ```bash
   gh repo deploy-key list --repo <org/repo>
   ```

2. **Test SSH connection:**
   ```bash
   ssh -T git@github.com
   ```

3. **Check SSH key exists:**
   ```bash
   ls -la ~/.ssh/
   cat ~/.ssh/id_ed25519.pub
   ```

4. **Re-register deploy key:**
   ```bash
   # From local machine
   gh repo deploy-key add .keys/<user>_<vm>.pub \
     --repo <org/repo> \
     --title "<user>@<vm>" \
     --allow-write
   ```

#### Issue: Cannot push to repository

**Symptoms:**
```
ERROR: Permission to org/repo.git denied to deploy key
```

**Solution:**
Deploy keys are read-only by default. Re-add with write access:

```bash
gh repo deploy-key add .keys/<user>_<vm>.pub \
  --repo <org/repo> \
  --title "<user>@<vm>" \
  --allow-write
```

### Performance Issues

#### Issue: VM is slow

**Diagnose:**
```bash
# Check CPU
top

# Check memory
free -h

# Check disk I/O
iostat -x 1

# Check disk space
df -h
```

**Solutions:**

1. **High CPU:**
   - Identify process: `ps aux --sort=-%cpu | head`
   - Kill if necessary: `kill <pid>`
   - Consider larger machine type

2. **Low memory:**
   - Check swap: `swapon --show`
   - Clear cache: `sudo sync && sudo sysctl vm.drop_caches=3`
   - Upgrade machine type

3. **Disk full:**
   - Clean backups: `sudo find /var/backups/ -mtime +7 -delete`
   - Clean logs: `sudo journalctl --vacuum-time=7d`
   - Increase disk size

#### Issue: High GCS costs

**Check usage:**
```bash
# List all files
gsutil ls -lhr gs://<bucket-name>/

# Check total size
gsutil du -sh gs://<bucket-name>/
```

**Solutions:**

1. **Reduce retention:**
   - Edit: `/opt/dev-monitoring/sync_dev_logs_to_gcs.sh`
   - Change: `RETENTION_DAYS=30` to lower value

2. **Compress logs:**
   ```bash
   # Compress before upload
   find /var/log/dev-activity/ -name "*.jsonl" -exec gzip {} \;
   ```

3. **Review lifecycle policy:**
   ```bash
   gsutil lifecycle get gs://<bucket-name>/
   ```

### Auto-Shutdown Issues

#### Issue: VM shuts down too quickly

**Adjust idle timeout:**
```bash
# Edit service file
sudo vi /etc/systemd/system/dev-activity.service

# Change: Environment="IDLE_SHUTDOWN_MINUTES=30"
# To higher value: Environment="IDLE_SHUTDOWN_MINUTES=60"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart dev-activity
```

#### Issue: VM doesn't shut down when idle

**Check activity daemon:**
```bash
systemctl status dev-activity
```

**Check recent activity:**
```bash
tail -f /var/log/dev-activity/*_activity.jsonl
```

**Possible causes:**
- Background processes running
- SSH session left open
- High CPU usage from system tasks

**Force shutdown test:**
```bash
# Stop activity daemon
sudo systemctl stop dev-activity

# Trigger manual shutdown (cancel within 1 minute)
sudo shutdown -h +1 "Test shutdown"
sudo shutdown -c  # Cancel
```

### Reporting Issues

#### Issue: Month-end report generation fails

**Check logs:**
```bash
./reporting/month_end_runner.sh config/users/<user>.yaml 2024-11
```

**Common causes:**

1. **VM not accessible:**
   ```bash
   # Start VM if stopped
   gcloud compute instances start <vm-name> --zone=<zone>
   ```

2. **No logs found:**
   ```bash
   # Check log directories on VM
   gcloud compute ssh <vm> --command="ls -la /var/log/dev-*/"
   ```

3. **Python dependencies:**
   ```bash
   # Install locally
   pip3 install pyyaml
   ```

### General Debugging

#### Enable verbose logging

**Activity daemon:**
```bash
# Edit service file
sudo vi /etc/systemd/system/dev-activity.service

# Add: Environment="DEBUG=1"

# Restart
sudo systemctl daemon-reload
sudo systemctl restart dev-activity
```

**Scripts:**
```bash
# Run with bash debug
bash -x /opt/dev-monitoring/dev_local_backup.sh
```

#### Check all services status

```bash
# Systemd services
systemctl list-units --type=service --state=running | grep dev

# Cron jobs
sudo grep -r "dev" /etc/cron.d/

# Recent log entries
sudo journalctl --since "1 hour ago" | grep -i dev
```

#### Collect diagnostic information

```bash
# Create diagnostic bundle
mkdir -p /tmp/diagnostics
systemctl status dev-activity > /tmp/diagnostics/service-status.txt
journalctl -u dev-activity -n 500 > /tmp/diagnostics/service-logs.txt
df -h > /tmp/diagnostics/disk-usage.txt
free -h > /tmp/diagnostics/memory.txt
ps aux > /tmp/diagnostics/processes.txt
ls -laR /var/log/dev-* > /tmp/diagnostics/log-listing.txt

# Download
gcloud compute scp --recurse <vm>:/tmp/diagnostics/ ./diagnostics/
```

## Getting Help

1. **Check this guide** first
2. **Review logs** for error messages
3. **Search issues** on GitHub (if applicable)
4. **Contact admin:** scott@brightfox.ai

Include in your support request:
- Developer username
- VM name and project
- Error messages (copy/paste)
- Steps to reproduce
- Diagnostic bundle (if requested)
