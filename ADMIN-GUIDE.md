# VM Administration Guide

**The single source of truth for provisioning and managing engineer VMs.**

---

## 🚀 Quick Start - Provision a New Engineer VM

### Step 1: Create Configuration

```bash
cp config/users/template.yaml config/users/<name>.yaml
```

Edit the file with engineer's details:
- `user.email` - Engineer's email
- `user.username` - First name (e.g., "akash")
- `vm.name` - VM name (e.g., "dev-akash-vm-001")

### Step 2: Run Build Script

```bash
./scripts/build-vm.sh config/users/<name>.yaml
```

**Duration:** ~40-45 minutes

**What it does:**
- Creates VM with Ubuntu 22.04 + GNOME Desktop
- Installs Chrome Remote Desktop + dbus-x11
- Sets up monitoring service (auto-deletes sudo files)
- Configures security (no sudo for engineer)
- Grants IAM permissions
- Creates static IP

### Step 3: Verify Security

```bash
./scripts/verify-security.sh <name> <vm-name> gcp-engg-vm us-east1-b
```

**Must pass all 13 tests!**

### Step 4: Send Onboarding Email

```bash
# Use the template
cp onboarding-emails/TEMPLATE-onboarding-email.txt onboarding-emails/dev-<name>-vm-001-COMPLETE-ONBOARDING.txt

# Replace placeholders:
# {{ENGINEER_NAME}}, {{VM_NAME}}, {{STATIC_IP}}, etc.

# Send to engineer
```

---

## 📋 Configuration Template

**Location:** `config/users/template.yaml`

**Required fields:**
```yaml
user:
  email: <email>
  username: <firstname>
  full_name: <Full Name>

vm:
  name: dev-<name>-vm-001
  project: gcp-engg-vm
  zone: us-east1-b
  machine_type: n2-standard-4
  disk_size_gb: 100

billing:
  account: 016B46-D56B18-B9B11D  # Google Credits - DO NOT CHANGE
```

---

## 🔒 Security Architecture

### Two-Layer Protection:

**Layer 1: Project Metadata (Primary)**
- `enable-oslogin-sudo=FALSE` at project level
- Prevents OS Login from creating sudo files
- Checked before every VM build

**Layer 2: Monitoring Service (Backup)**
- Runs on boot for 5 minutes
- Checks every 10 seconds (30 checks)
- Auto-deletes any engineer sudo files
- Logs activity to `/var/log/sudo-monitor.log`

### 🚨 CRITICAL: NEVER Grant `roles/compute.instanceAdmin.v1`

**WARNING:** If an engineer has BOTH of these roles:
- `roles/compute.osLogin` (for SSH)
- `roles/compute.instanceAdmin.v1` (for VM management)

**GCP will AUTOMATICALLY grant them passwordless sudo** via OS Login, creating `/var/google-sudoers.d/<username>` files.

**✅ Correct IAM Configuration:**
- `projects/gcp-engg-vm/roles/CustomEngineerRole` (start/stop/reset/get/list VMs)
- `roles/compute.osLogin` (SSH access)
- `roles/iam.serviceAccountUser` (on VM service account)

**❌ DO NOT GRANT:**
- `roles/compute.instanceAdmin.v1` (auto-grants sudo)
- `roles/compute.osAdminLogin` (admin-level sudo)
- Any other `compute.*Admin` roles

**Detection:** The `verify-security.sh` script now checks for `instanceAdmin.v1` as Test #1.

---

### Security Verification (6 Tests):

1. ✅ **IAM Roles** - No instanceAdmin.v1 (CRITICAL)
2. ✅ Project metadata set correctly
3. ✅ No problematic sudoers entries
4. ✅ No OS Login sudo file exists
5. ✅ Static IP assigned
6. ✅ SSH access works

---

## 📁 Directory Structure

```
GCP-Engg_VM/
├── ADMIN-GUIDE.md              # ← You are here
├── README.md                   # Project overview
├── config/
│   └── users/
│       ├── template.yaml       # Template for new VMs
│       ├── akash.yaml
│       └── ankush.yaml
├── scripts/
│   ├── build-vm.sh             # Main build script
│   ├── verify-security.sh      # Security audit
│   ├── monitor-sudo-removal.sh # Monitoring service
│   └── sudo-monitor.service    # Systemd service
├── onboarding-emails/
│   ├── README.md               # How to use
│   ├── TEMPLATE-onboarding-email.txt
│   └── dev-*-COMPLETE-ONBOARDING.txt
├── docs/                       # Reference documentation
└── archive/                    # Historical files
```

---

## 🛠️ Common Tasks

### Check VM Status

```bash
gcloud compute instances describe <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --format="value(status,networkInterfaces[0].accessConfigs[0].natIP)"
```

### Start/Stop VM

```bash
# Start
gcloud compute instances start <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# Stop
gcloud compute instances stop <vm-name> --project=gcp-engg-vm --zone=us-east1-b
```

### SSH into VM

```bash
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b
```

### Check Monitoring Service

```bash
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b --command="
sudo systemctl status sudo-monitor.service
sudo journalctl -u sudo-monitor.service -n 20
"
```

### Rebuild a VM

```bash
# Delete VM (keeps static IP and config)
gcloud compute instances delete <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# Rebuild using existing config
./scripts/build-vm.sh config/users/<name>.yaml
```

---

## 🐛 Troubleshooting

### VM Build Fails at Pre-flight Check

**Error:** "Project metadata enable-oslogin-sudo is NOT set to FALSE"

**Fix:**
```bash
gcloud compute project-info add-metadata \
  --project=gcp-engg-vm \
  --metadata=enable-oslogin-sudo=FALSE
```

### Security Audit Fails

**Check which test failed:**
```bash
./scripts/verify-security.sh <name> <vm-name> gcp-engg-vm us-east1-b
```

**Common issues:**
- Engineer still has sudo: Remove from groups manually
- Monitoring service not running: `systemctl restart sudo-monitor`
- Permissions wrong: Re-run build script section

### Engineer Can't SSH

**Verify IAM permissions (need ALL 3):**
```bash
# 1. Start/stop VMs
gcloud projects get-iam-policy gcp-engg-vm --flatten="bindings[].members" --filter="bindings.members:<email>"

# Should show:
# - roles/compute.instanceAdmin.v1
# - roles/compute.osLogin
# - roles/iam.serviceAccountUser (on VM service account)
```

**Re-grant if missing:**
```bash
gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:<email>" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:<email>" \
  --role="roles/compute.osLogin"

SERVICE_ACCOUNT=$(gcloud compute instances describe <vm-name> --project=gcp-engg-vm --zone=us-east1-b --format="get(serviceAccounts[0].email)")
gcloud iam service-accounts add-iam-policy-binding $SERVICE_ACCOUNT \
  --project=gcp-engg-vm \
  --member="user:<email>" \
  --role="roles/iam.serviceAccountUser"
```

---

## 📞 Support

**For issues:**
1. Check this guide
2. Review `docs/Troubleshooting.md`
3. Check recent changes in `archive/`

**Contact:** scott@brightfox.ai

---

## ✅ That's It!

**To provision a new engineer VM:**
1. Copy template config
2. Run build script (~45 min)
3. Verify security (all 13 tests pass)
4. Send onboarding email

**Simple, secure, repeatable.**
