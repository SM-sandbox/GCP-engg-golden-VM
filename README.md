# GCP Engineer VM Platform

**Production-grade infrastructure for automated developer VM provisioning on Google Cloud Platform**

Complete infrastructure for creating isolated developer VMs with automated monitoring, security enforcement, backup, and Chrome Remote Desktop access.

---

## 🚀 Quick Start

### For Administrators - Provision a New Engineer VM

```bash
# 1. Create user configuration
cp config/users/template.yaml config/users/<name>.yaml
# Edit with engineer's details (email, name, machine type)

# 2. Build VM (~5 minutes)
./src/provisioning/build-vm.sh config/users/<name>.yaml

# 3. Verify security (must pass all tests)
./src/security/verify-security.sh <username> <vm-name> gcp-engg-vm us-east1-b

# 4. Setup Chrome Remote Desktop (requires engineer's OAuth code)
./src/provisioning/setup-crd.sh <vm-name> <username> <oauth-code>

# 5. Send onboarding email (auto-generated)
cat artifacts/onboarding-emails/<vm-name>-onboarding.txt
```

**See [ADMIN-GUIDE.md](ADMIN-GUIDE.md) for complete documentation.**

---

## 📁 Repository Structure

```
gcp-engineer-vm-platform/
│
├── bin/                           # CLI tools (future)
├── config/                        # Configuration management
│   ├── users/                     # Per-user VM configurations
│   ├── project/                   # GCP project settings
│   └── schema/                    # Config validation schemas
│
├── src/                           # Source code
│   ├── provisioning/              # VM creation & setup
│   │   ├── build-vm.sh           # Main build orchestrator
│   │   ├── setup-crd.sh          # Chrome Remote Desktop
│   │   ├── install-apps.sh       # Application installation
│   │   ├── finalize-vm.sh        # Final security hardening
│   │   └── ...
│   │
│   ├── monitoring/                # Activity tracking & auto-shutdown
│   │   ├── install-monitoring.sh
│   │   ├── dev-activity-daemon.py
│   │   ├── dev-git-stats.py
│   │   └── ...
│   │
│   ├── security/                  # Security verification
│   │   ├── verify-security.sh    # Security audit
│   │   └── validate-deployment.sh
│   │
│   ├── golden-image/              # Golden image creation
│   │   └── create-gnome-image.sh
│   │
│   ├── onboarding/                # Engineer onboarding
│   │   ├── generate-email.sh
│   │   └── templates/
│   │
│   └── utils/                     # Shared utilities
│       ├── config-parser.sh
│       └── gcloud-helpers.sh
│
├── tests/                         # Testing framework
│   ├── integration/               # Full lifecycle tests
│   ├── security/                  # Security tests
│   └── fixtures/                  # Test data
│
├── docs/                          # Documentation
│   ├── architecture/              # System design
│   ├── operations/                # Operational guides
│   └── development/               # Developer docs
│
└── artifacts/                     # Generated files (gitignored)
    ├── builds/                    # Build logs
    ├── onboarding-emails/         # Generated emails
    └── reports/                   # Test reports
```

---

## 🔒 Security Architecture

### Native IAM Security (No Sudo Access)

Engineers get controlled permissions via Google Cloud IAM:

**Granted Roles:**
- ✅ `CustomEngineerRole` - Start/Stop/Reset VMs
- ✅ `roles/compute.osLogin` - SSH access
- ✅ `roles/iam.serviceAccountUser` - Use VM service account
- ✅ `roles/iap.tunnelResourceAccessor` - IAP TCP forwarding

**Never Granted:**
- ❌ `roles/compute.instanceAdmin.v1` - Would grant implicit sudo
- ❌ `roles/compute.osAdminLogin` - Admin-level sudo
- ❌ Any other admin roles

**Project-level Protection:**
- `enable-oslogin-sudo=FALSE` - Prevents OS Login from creating sudo files
- Verified before every VM build

**See [docs/operations/SUDO_SECURITY_LEARNINGS.md](docs/operations/SUDO_SECURITY_LEARNINGS.md) for details.**

---

## 🎯 Key Features

### For Administrators
- ✅ **Single-command VM provisioning** - Fully automated builds
- ✅ **Native IAM security** - No fragile monitoring scripts
- ✅ **Comprehensive verification** - 13-point security audit
- ✅ **Golden image support** - Fast cloning from pre-built images
- ✅ **Activity monitoring** - Auto-shutdown after 30min idle
- ✅ **Git statistics** - LOC tracking per repository
- ✅ **Automated backups** - Daily snapshots with 7-day retention

### For Engineers
- ✅ **Full desktop environment** - Chrome Remote Desktop (GNOME)
- ✅ **No sudo needed** - AppImage installs work great
- ✅ **Remote development** - Windsurf/VS Code compatible
- ✅ **Pre-installed tools** - Chrome, Python, Node.js, Git, Azure CLI
- ✅ **Cost efficient** - Auto-shutdown prevents runaway costs

---

## 📊 Monitoring & Automation

### Activity Daemon
- Monitors file changes, CPU usage, process activity
- Auto-shutdown after 30 minutes of inactivity
- Logs to `/var/log/dev-activity/`
- Syncs logs to GCS bucket

### Git Statistics
- Hourly LOC tracking per repository
- Commit counting and author tracking
- Monthly reporting

### Backups
- Daily at 2 AM local time
- Tar.gz snapshots to `/var/backups/dev-repos/`
- 7-day local retention
- GCS backup available

---

## 🛠️ Common Tasks

### Check VM Status
```bash
gcloud compute instances describe <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b
```

### Start/Stop VM
```bash
gcloud compute instances start <vm-name> --project=gcp-engg-vm --zone=us-east1-b
gcloud compute instances stop <vm-name> --project=gcp-engg-vm --zone=us-east1-b
```

### SSH into VM
```bash
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b
```

### Check Monitoring
```bash
gcloud compute ssh <vm-name> --command="systemctl status dev-activity"
```

---

## 📚 Documentation

- **[ADMIN-GUIDE.md](ADMIN-GUIDE.md)** - Complete administration guide (start here!)
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes
- **[docs/operations/](docs/operations/)** - Operational guides & troubleshooting
- **[docs/architecture/](docs/architecture/)** - System design documentation
- **[docs/development/](docs/development/)** - Developer contribution guide

---

## 🔄 Version History

**v2.0.0** (December 2025)
- Complete repository restructuring for production readiness
- Clean separation of concerns (provisioning/monitoring/security)
- Added IAP Tunnel Resource Accessor role for TCP forwarding
- Improved documentation and operational guides

**v1.0** (November 2024)
- Initial release with native IAM security
- Chrome Remote Desktop support
- Activity monitoring and auto-shutdown

---

## 💡 Design Principles

1. **Single Source of Truth** - No duplication, one canonical location per file
2. **Clear Separation** - Each directory has one well-defined purpose
3. **Production Ready** - Follows infrastructure-as-code best practices
4. **Self-Documenting** - Structure and naming explain purpose
5. **Security First** - IAM-based permissions, no sudo access

---

## 📞 Support

**For issues:**
1. Check [ADMIN-GUIDE.md](ADMIN-GUIDE.md)
2. Review [docs/operations/Troubleshooting.md](docs/operations/Troubleshooting.md)
3. Contact: scott@brightfox.ai

---

## 📄 License

Proprietary - BrightFox AI

---

**Simple. Secure. Repeatable.**
