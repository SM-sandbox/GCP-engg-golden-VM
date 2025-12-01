# 🚀 Developer VM - Getting Started Guide

**Welcome to your dedicated Google Cloud development environment!**

---

## 🎯 What You're Getting

You have a **fully configured GCP VM** set up with:

✅ **Pre-installed Development Tools**
- Python 3.x with virtual environments
- Node.js (if configured)
- Git and GitHub SSH access
- Google Cloud SDK (gcloud, gsutil)
- Essential development packages

✅ **Your Repositories** (automatically cloned)
- GitHub deploy key configured
- Ready to push/pull
- No manual SSH setup needed

✅ **Cloud Storage Access**
- Direct GCS access via gsutil
- No authentication needed
- Fast data transfer

✅ **Auto Time Tracking** (automatic)
- Tracks boot-to-shutdown for billing
- Monthly payment reports
- Auto-shutdown when idle (30 min)

✅ **Automatic Backups**
- Local backups (daily 2 AM)
- GCS log sync (daily 3 AM)
- 6-month retention for billing

---

## 📋 What Scott Will Provide You

You'll receive:

1. **VM Connection Details**
   - VM name (e.g., `test-vm-001`)
   - Static IP address
   - Zone (e.g., `us-east1-b`)
   - Your Linux username

2. **Configuration File**
   - Your `<username>.yaml` config
   - Shows all your settings

3. **This Getting Started Guide**

4. **Windsurf Remote Setup Guide** (separate file)

---

## 🖥️ Your VM Specifications

**Standard Configuration:**
- **Machine Type:** n2-standard-4
- **CPUs:** 4 vCPUs
- **RAM:** 16 GB
- **Disk:** 100 GB SSD
- **OS:** Debian 11
- **Network:** Premium tier, static IP

**Monthly Cost:** ~$130-150 (auto-shutdown saves ~40%)

---

## 🏗️ What's Already Set Up

When you receive your VM, **everything is ready**:

### 1. **Your User Account**
```
Username: <your_email_with_underscores>
Example: jerry_brightfox_ai
Home: /home/<username>
```

### 2. **Directory Structure**
```
/home/<username>/
├── projects/              # Your cloned repositories
│   └── <repo-name>/       # Auto-cloned from GitHub
├── .venv/                 # Python virtual environments
│   └── default/           # Pre-configured venv
└── backups/               # Local backup storage
```

### 3. **GitHub Access**
- Deploy key generated and registered
- Read/write access to your assigned repos
- No password/token needed

### 4. **Python Environment**
```bash
# Already activated in your .bashrc
source ~/.venv/default/bin/activate
```

### 5. **Installed Packages**
- All system packages from your config
- Python dependencies from requirements.txt (if provided)
- Language-specific tools (Go, Rust, etc. if configured)

---

## 🚀 Quick Start - First Time Setup

### Step 1: Install Google Cloud SDK (Your Laptop)

**Mac/Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Windows:**
Download from: https://cloud.google.com/sdk/docs/install

### Step 2: Authenticate with Google Cloud

```bash
gcloud auth login --no-launch-browser
```

**Follow the prompts:**
1. Copy the URL that appears
2. Open in your browser
3. Sign in with your Google account
4. Copy the verification code
5. Paste it back in terminal

### Step 3: Set Your Project

```bash
# Scott will provide the PROJECT_ID
gcloud config set project <PROJECT_ID>

# Example:
gcloud config set project gcp-engg-vm
```

### Step 4: Connect to Your VM

```bash
# Scott will provide these values
VM_NAME="<YOUR_VM_NAME>"
ZONE="<YOUR_ZONE>"
USERNAME="<YOUR_USERNAME>"  # Your username

# Connect via SSH
gcloud compute ssh $USERNAME@$VM_NAME \
  --zone=$ZONE \
  --project=<PROJECT_ID>
```

**First connection:**
- May ask to generate SSH keys (say yes)
- May ask to add to known_hosts (type yes)
- Takes 10-30 seconds

**You're connected when you see:**
```
<username>@<vm-name>:~$
```

---

## 💻 Your Daily Workflow

### Every Time You Want to Work

**1. Connect to VM:**
```bash
gcloud compute ssh <username>@<vm-name> \
  --zone=<zone> \
  --project=<project-id>
```

**2. Navigate to Your Project:**
```bash
cd ~/projects/<repo-name>
```

**3. Your Python Environment is Auto-Activated:**
```bash
# Already active from .bashrc
# Shows: (default) in your prompt
which python
# /home/<username>/.venv/default/bin/python
```

**4. Start Coding!**
```bash
# Edit files
vim main.py
# Or use Windsurf (see WINDSURF_REMOTE_SETUP.md)

# Run your code
python main.py

# Commit changes
git add .
git commit -m "Add feature"
git push origin main
```

**5. Disconnect:**
```bash
exit
```

---

## 🔄 Working with Git

### Your Repo is Already Cloned

```bash
cd ~/projects/<repo-name>
```

### Make Changes and Push

```bash
# Check status
git status

# Create a branch
git checkout -b feature/my-feature

# Make changes, then commit
git add .
git commit -m "Add new feature"

# Push to GitHub
git push origin feature/my-feature
```

**No password/token needed!** Deploy key is already configured.

### Pull Latest Changes

```bash
cd ~/projects/<repo-name>
git pull origin main
```

---

## 📦 Managing Python Dependencies

### Your Default Virtual Environment

```bash
# Already activated automatically
source ~/.venv/default/bin/activate

# Install new packages
pip install pandas numpy
pip freeze > requirements.txt
```

### Create Project-Specific Environments

```bash
# In your project directory
cd ~/projects/<repo-name>

# Create new venv
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

---

## ☁️ Using Google Cloud Storage

### Access GCS Directly

```bash
# List your buckets
gsutil ls

# List files in a bucket
gsutil ls gs://<bucket-name>/

# Download a file
gsutil cp gs://<bucket>/file.json .

# Upload a file
gsutil cp output.json gs://<bucket>/results/

# Sync a directory
gsutil -m rsync -r ./data/ gs://<bucket>/data/
```

**No authentication needed!** VM has service account access.

---

## 🛡️ Auto-Shutdown Protection

Your VM automatically shuts down after **30 minutes of inactivity** to save costs.

### ✅ VM Stays Running When:
- Files are being modified
- CPU usage > 10%
- Python/Node processes active
- SSH session connected
- Git operations in progress

### ❌ VM Shuts Down When:
- No file changes for 30 minutes
- Low CPU usage
- No active processes
- No SSH session

### If VM Shuts Down:

**Don't worry!** Your work is backed up automatically.

**To restart:**
```bash
# From your laptop
gcloud compute instances start <vm-name> \
  --zone=<zone> \
  --project=<project-id>

# Wait 30 seconds, then reconnect
gcloud compute ssh <username>@<vm-name> \
  --zone=<zone> \
  --project=<project-id>
```

**Your files are safe:**
- Local backup (daily 2 AM)
- GCS backup (daily 3 AM)
- Pre-shutdown backup (before idle shutdown)

---

## 🎨 Using Windsurf IDE (Recommended)

**For the best experience**, use Windsurf to connect remotely:

👉 **See:** `WINDSURF_REMOTE_SETUP.md` for complete setup

**Benefits:**
- Edit code in a familiar IDE
- Terminal runs on the VM
- Git integration
- AI coding assistant
- Multiple terminals
- File explorer

**Quick Overview:**
1. Install Windsurf on your laptop
2. Install "Remote - SSH" extension
3. Configure SSH connection
4. Connect and work remotely

**You'll feel like you're working locally, but everything runs on the VM!**

---

## ⏱️ Auto Time Tracking

**Simple and automatic billing tracking.**

Your VM automatically tracks your work time:
- Records when you boot up the VM
- Records when you shut down the VM
- Calculates hours worked (boot-to-shutdown time)

At the end of each month, a payment report is automatically generated and sent to billing.

**That's it!** No manual time tracking needed. Just work on your VM and billing is handled automatically.

---

## 🔧 Common Tasks

### Install Additional Python Packages

```bash
# Activate your environment
source ~/.venv/default/bin/activate

# Install packages
pip install requests beautifulsoup4

# Or from requirements
pip install -r requirements.txt

# Update requirements
pip freeze > requirements.txt
```

### Run Long-Running Jobs

**Use tmux to keep jobs running after disconnect:**

```bash
# Start tmux session
tmux new -s work

# Run your job
python long_running_script.py

# Detach: Ctrl+b then d
# Now you can disconnect

# Later, reconnect and reattach
gcloud compute ssh <username>@<vm-name> ...
tmux attach -s work
```

### Check System Resources

```bash
# CPU and memory usage
htop

# Disk space
df -h

# Running processes
ps aux | grep python

# Network activity
nethogs
```

### View Auto-Shutdown Status

```bash
# Check activity daemon logs
sudo journalctl -u dev-activity -n 50

# View activity log
tail -20 /var/log/dev-activity/<username>_activity.jsonl
```

---

## 🐛 Troubleshooting

### Can't Connect via SSH

**Solution 1: Check VM is running**
```bash
gcloud compute instances describe <vm-name> \
  --zone=<zone> \
  --project=<project-id> \
  --format="get(status)"

# If TERMINATED, start it
gcloud compute instances start <vm-name> \
  --zone=<zone> \
  --project=<project-id>
```

**Solution 2: Regenerate SSH keys**
```bash
gcloud compute config-ssh --remove
gcloud compute config-ssh
```

### Permission Denied (GitHub)

**Check deploy key:**
```bash
ssh -T git@github.com
# Should show: "Hi <username>! You've successfully authenticated..."
```

**If fails, contact Scott to verify deploy key registration**

### Python Package Not Found

**Make sure venv is activated:**
```bash
which python
# Should show: /home/<username>/.venv/default/bin/python

# If not:
source ~/.venv/default/bin/activate
```

### GCS Access Denied

**Check service account permissions:**
```bash
gcloud auth list
# Should show service account

# Test access
gsutil ls gs://<bucket>/
```

**If fails, contact Scott to verify service account permissions**

### VM Shut Down During Work

**This shouldn't happen if you're actively working.**

**To prevent:**
- Keep SSH connected
- Use tmux for long jobs
- Ensure files are being modified

**If it happens:**
- All work is backed up (pre-shutdown backup)
- Restart VM and reconnect
- Your files are safe

---

## 📁 Your Configuration

Scott configured your VM based on this YAML file:

**Example: `example_user.yaml`**
```yaml
vm:
  name: test-vm-001
  zone: us-east1-b
  machine_type: n2-standard-4

user:
  username: jerry_brightfox_ai
  github_email: jerry@brightfox.ai

repositories:
  - name: gcp-eng-vm-test-repo
    url: git@github.com:BrightFoxAI/gcp-eng-vm-test-repo.git

languages:
  python:
    version: "3.11"
    venv_name: default

monitoring:
  activity_daemon:
    enabled: true
    idle_shutdown_minutes: 30
```

**To see your full config:** Ask Scott for your YAML file

---

## 📞 Getting Help

### Check the Docs

1. **This file** - General usage
2. **`WINDSURF_REMOTE_SETUP.md`** - IDE setup
3. **`README.md`** - System overview
4. **`docs/Troubleshooting.md`** - Detailed troubleshooting

### Contact Scott

**Email:** scott@brightfox.ai

**When asking for help, provide:**
- Your VM name
- What you're trying to do
- Error message (if any)
- Output of: `gcloud compute instances describe <vm-name> ...`

---

## ✅ Quick Reference

### Connection Command
```bash
gcloud compute ssh <username>@<vm-name> \
  --zone=<zone> \
  --project=<project-id>
```

### Your Directory Structure
```
~/ (your home directory)
├── projects/<repo-name>/    # Your code
├── .venv/default/           # Python environment
└── backups/                 # Local backups
```

### Essential Commands
```bash
# Connect to VM
gcloud compute ssh <username>@<vm-name> --zone=<zone>

# Navigate to project
cd ~/projects/<repo-name>

# Activate Python venv (auto-activated in .bashrc)
source ~/.venv/default/bin/activate

# Run code
python script.py

# Git operations
git status
git add .
git commit -m "message"
git push origin main

# GCS operations
gsutil ls gs://<bucket>/
gsutil cp file.txt gs://<bucket>/

# Disconnect
exit
```

---

## 🎉 You're Ready!

**Your development environment is fully set up and ready to use.**

### Next Steps:

1. ✅ **Connect to your VM** (see Step 4 above)
2. ✅ **Explore your projects** (`cd ~/projects`)
3. ✅ **Set up Windsurf** (see `WINDSURF_REMOTE_SETUP.md`)
4. ✅ **Start coding!**

**Happy coding! 🚀**

---

**Questions?** Contact Scott at scott@brightfox.ai
