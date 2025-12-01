# VM Onboarding Guide

## Overview

This guide walks through the complete process of onboarding a new developer to a GCP VM.

## Prerequisites

On your local machine (Mac):
- `gcloud` CLI installed and authenticated
- `gh` CLI installed and authenticated
- `yq` and `jq` installed
- SSH access configured

## Step-by-Step Onboarding

### 1. Create Developer Configuration

```bash
cd dev-vm-infra
cp config/users/jerry.yaml config/users/<newdev>.yaml
```

Edit the file:

```yaml
vm:
  project_id: gcp-engg-vm-<newdev>  # Unique project ID
  zone: us-east1-b
  name: dev-vm-<newdev>
  machine_type: n2-standard-4
  boot_disk_gb: 100

users:
  admin:
    username: scott
  developer:
    username: <newdev>
    email: <newdev>@brightfox.ai

repos:
  - BrightFoxAI/repo1
  - BrightFoxAI/repo2

gcs_sync:
  enabled: true
  bucket: <newdev>-dev-vm-backups
```

### 2. Verify GCloud Access

```bash
./bootstrap/gcloud_prechecks.sh
```

Should show:
- ✓ gcloud installed
- ✓ Authenticated
- ✓ Project access granted

### 3. Bootstrap VM

This creates the GCP project, VM instance, users, and SSH keys:

```bash
./bootstrap/bootstrap_dev_vm.sh config/users/<newdev>.yaml
```

**What this does:**
- Creates or verifies GCP project
- Enables required APIs (Compute Engine, Storage)
- Creates VM instance with specified machine type
- Creates admin user (scott) with sudo
- Creates developer user (no sudo)
- Generates SSH keypair on VM for GitHub access
- Retrieves public key to `.keys/` directory
- Registers deploy keys for each repository

**Duration:** ~5-10 minutes

### 4. Environment Provisioning

This installs all packages, sets up directories, and configures the environment:

```bash
./bootstrap/ensure_env_from_config.sh config/users/<newdev>.yaml
```

**What this does:**
- Updates system packages
- Installs apt packages (git, python3, nodejs, etc.)
- Installs cloud SDKs (gcloud, gh, az, azd)
- Installs optional languages (Go, Rust if enabled)
- Creates directory structure
- Sets up Python virtualenvs
- Installs JupyterLab
- Configures shell environment (.bashrc)
- Clones repositories

**Duration:** ~10-15 minutes

### 5. Deploy Monitoring

This installs activity tracking, git stats, backup, and GCS sync:

```bash
./vm-scripts/install_monitoring.sh config/users/<newdev>.yaml
```

**What this does:**
- Installs Python dependencies (psutil)
- Deploys monitoring scripts to `/opt/dev-monitoring/`
- Installs systemd service for activity daemon
- Sets up cron jobs for git stats, backups, GCS sync
- Configures shutdown permissions
- Starts activity monitoring daemon

**Duration:** ~2-3 minutes

### 6. Verify Installation

Check that everything is running:

```bash
# SSH into the VM
gcloud compute ssh dev-vm-<newdev> --zone=us-east1-b

# Check activity daemon
sudo systemctl status dev-activity

# Check logs
tail -f /var/log/dev-activity/*_activity.jsonl

# Check git stats
ls -la /var/log/dev-git/

# Verify Python venv
source ~/envs/jupyter-env/bin/activate
jupyter lab --version

# Check repositories
ls -la ~/projects/
```

### 7. Configure Jupyter (Optional)

If the developer will use Jupyter:

```bash
# On the VM
source ~/envs/jupyter-env/bin/activate
jupyter lab --generate-config

# Edit ~/.jupyter/jupyter_lab_config.py
# Set password, enable remote access, etc.

# Start Jupyter
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
```

Configure GCP firewall rule to allow port 8888.

### 8. Developer Access

Provide the developer with:

1. **SSH Access:**
   ```bash
   gcloud compute ssh dev-vm-<newdev> --zone=us-east1-b
   ```

2. **Project Information:**
   - GCP Project: `gcp-engg-vm-<newdev>`
   - VM Name: `dev-vm-<newdev>`
   - Zone: `us-east1-b`

3. **Directories:**
   - Projects: `~/projects/`
   - Python envs: `~/envs/`
   - Personal scripts: `~/bin/`

4. **Important Notes:**
   - VM auto-shuts down after 30 minutes of inactivity
   - Backups run daily at 2 AM
   - Git stats collected hourly
   - No sudo access (contact admin if needed)

## Troubleshooting

### SSH Connection Failed

```bash
# Check VM is running
gcloud compute instances describe dev-vm-<newdev> --zone=us-east1-b

# Start if stopped
gcloud compute instances start dev-vm-<newdev> --zone=us-east1-b
```

### Repository Clone Failed

Deploy keys may not be properly configured:

```bash
# Re-add deploy keys
gh repo deploy-key add .keys/<newdev>_dev-vm-<newdev>.pub \
  --repo BrightFoxAI/repo-name \
  --title "<newdev>@dev-vm-<newdev>" \
  --allow-write
```

### Activity Daemon Not Running

```bash
# SSH into VM
gcloud compute ssh dev-vm-<newdev> --zone=us-east1-b

# Check status
sudo systemctl status dev-activity

# Restart
sudo systemctl restart dev-activity

# Check logs
sudo journalctl -u dev-activity -n 50
```

### GCS Sync Failed

```bash
# Verify bucket exists
gsutil ls gs://<newdev>-dev-vm-backups

# Create if missing
gsutil mb -c standard -l us-east1 gs://<newdev>-dev-vm-backups

# Test sync manually
sudo bash /opt/dev-monitoring/sync_dev_logs_to_gcs.sh
```

## Offboarding

When a developer leaves:

1. **Backup all data:**
   ```bash
   # Manual backup before shutdown
   gcloud compute ssh dev-vm-<newdev> --command="sudo /opt/dev-monitoring/dev_local_backup.sh"
   
   # Download final logs
   ./reporting/month_end_runner.sh config/users/<newdev>.yaml
   ```

2. **Archive VM:**
   ```bash
   # Create disk snapshot
   gcloud compute disks snapshot dev-vm-<newdev> \
     --snapshot-names=dev-vm-<newdev>-final \
     --zone=us-east1-b
   
   # Stop VM
   gcloud compute instances stop dev-vm-<newdev> --zone=us-east1-b
   ```

3. **Remove access:**
   - Remove deploy keys from GitHub repositories
   - Delete VM (optional, or keep stopped)
   - Archive GCS bucket

4. **Generate final report:**
   ```bash
   ./reporting/month_end_runner.sh config/users/<newdev>.yaml $(date +%Y-%m)
   ```

## Monthly Maintenance

For all active developers:

```bash
# Generate reports
for config in config/users/*.yaml; do
  ./reporting/month_end_runner.sh "$config"
done

# Review costs
gcloud compute instances list --format="table(name,zone,machineType,status)"

# Check for idle VMs
# (Activity daemon should auto-shutdown, but verify)
```
