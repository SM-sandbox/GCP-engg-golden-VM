# <USER_NAME> VM - Admin Files

**Developer:** <USER_NAME> (<USER_EMAIL>)
**VM Name:** <VM_NAME>
**Created:** <DATE>

---

## 📁 Contents

- **`<USER_USERNAME>.yaml`** - Complete VM configuration file

---

## 🚀 Provisioning Commands

### 1. Pre-flight Checks
```bash
cd <REPO_ROOT>/GCP-Engg_VM
./bootstrap/gcloud_prechecks.sh
```

### 2. Provision VM
```bash
./bootstrap/bootstrap_dev_vm.sh config/users/<USER_USERNAME>.yaml
```

### 3. Install Environment
```bash
./bootstrap/ensure_env_from_config.sh config/users/<USER_USERNAME>.yaml
```

### 4. Install Monitoring
```bash
./vm-scripts/install_monitoring.sh config/users/<USER_USERNAME>.yaml
```

### 5. Get Static IP
```bash
gcloud compute instances describe <VM_NAME> \
  --zone=<ZONE> \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

**Update the static IP in:** `../user-package/VM_CONNECTION_INFO.txt`

---

## ✅ Verification Checklist

After provisioning:

- [ ] VM is running: `gcloud compute instances list --filter="name:<VM_NAME>"`
- [ ] Can SSH: `gcloud compute ssh <USER_USERNAME>@<VM_NAME> --zone=<ZONE>`
- [ ] Repos cloned: Check `/home/<USER_USERNAME>/projects/`
- [ ] Python venv exists: Check `/home/<USER_USERNAME>/.venv/default/`
- [ ] Monitoring running: `sudo systemctl status dev-activity`
- [ ] GitHub access: Run `ssh -T git@github.com` on VM
- [ ] Static IP recorded in user package

---

## 📦 Send to Engineer

Once provisioning is complete:

1. Update static IP in `../user-package/VM_CONNECTION_INFO.txt`
2. Zip the user-package directory:
   ```bash
   cd ../user-package
   zip -r <USER_USERNAME>-vm-onboarding.zip .
   ```
3. Email to: <USER_EMAIL>
4. Use email template from `onboarding/emails/templates/TEMPLATE_ONBOARDING_EMAIL.md`

---

## 📊 Configuration Summary

**VM Specs:**
- Machine: n2-standard-4 (4 vCPU, 16GB RAM)
- Disk: 100GB SSD
- OS: Ubuntu 22.04 LTS
- Zone: <ZONE>
- Cost: ~$130-150/month

**Billing:**
- Hourly Rate: $75/hour
- Auto time tracking: boot-to-shutdown
- Idle penalty: $0.50 per auto-shutdown
- Monthly reports generated

**Auto-Shutdown:**
- Idle threshold: 30 minutes
- Pre-shutdown backup: Yes
- Activity detection: CPU, file changes, SSH sessions

**Backups:**
- Local: Daily 2 AM, 7-day retention
- GCS: Daily 3 AM, 180-day retention
- Bucket: <VM_NAME>-backups

---

## 🔧 Repository Configuration

**IMPORTANT:** Update the repository URL in `<USER_USERNAME>.yaml` before provisioning!

Current placeholder:
```yaml
repositories:
  - name: your-main-repo
    url: git@github.com:BrightFoxAI/your-main-repo.git
```

**Action Required:** Replace `your-main-repo` with actual repository name(s).

---

## 📝 Notes

- Static IP will be assigned during provisioning
- GitHub deploy key will be auto-generated and needs to be added to repo
- User will receive onboarding package after static IP is updated

---

**Status:** Ready for provisioning (update repository URLs first)
