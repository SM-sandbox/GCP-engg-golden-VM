# Changelog

All notable changes to the GCP Engineer VM Platform will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.1.0] - 2025-12-01

### 🖥️ NoMachine Remote Desktop Support

**New Feature:** Added NoMachine as an alternative to Chrome Remote Desktop for engineers who need lower latency and full keyboard shortcut support.

### Added

- **NoMachine Installation Script** (`src/provisioning/install-nomachine.sh`)
  - Automated NoMachine server installation on existing VMs
  - Downloads latest version from official NoMachine site
  - Configures systemd service for auto-start

- **NoMachine Firewall Script** (`src/provisioning/setup-nomachine-firewall.sh`)
  - Creates GCP firewall rule for NoMachine ports (4000, 4011-4020)
  - Tags VMs with `nomachine-enabled` for targeted access
  - Idempotent - safe to run multiple times

- **Engineer Email Template** (`artifacts/NOMACHINE-SETUP-EMAIL.txt`)
  - Complete setup instructions for engineers
  - Connection details and troubleshooting guide

### Why NoMachine?

Chrome Remote Desktop works through a browser tab, which causes:
- Keyboard shortcuts intercepted by Chrome (Ctrl+C, Ctrl+V, etc.)
- Lag due to webpage-based streaming
- Less responsive UI for intensive coding work

NoMachine provides:
- Native application with direct key passthrough
- Lower latency NX protocol
- Better performance for development work
- File transfer support

### Usage

```bash
# For existing VMs (manual)
./src/provisioning/install-nomachine.sh <vm-name>
./src/provisioning/setup-nomachine-firewall.sh <vm-name>

# Engineers then download NoMachine client from:
# https://www.nomachine.com/download
```

---

## [2.0.0] - 2025-12-01

### 🎯 Major Restructure - Production-Ready Organization

**Breaking Changes:**
- Complete repository restructure with new directory layout
- Scripts moved from root-level to organized `src/` directory
- Clean separation of concerns (provisioning/monitoring/security/golden-image)

**Migration from v1.0:**
- Old repo preserved at: `GCP-Engg_VM-v2-sudo-first`
- New repo location: `GCP-engg-golden-VM`
- All functionality maintained, only structure changed

### Added

- **IAP Tunnel Support** - Added `roles/iap.tunnelResourceAccessor` permission
  - Fixes Error 4033: 'not authorized' for IAP TCP forwarding
  - Automatically granted during VM provisioning
  - Required for `setup-crd.sh` with `--tunnel-through-iap` flag

- **World-Class Structure**
  - `src/provisioning/` - VM creation and setup scripts
  - `src/monitoring/` - Activity tracking and auto-shutdown
  - `src/security/` - Security verification and validation
  - `src/golden-image/` - Golden image creation (separated from operations)
  - `src/onboarding/` - Engineer onboarding automation
  - `src/utils/` - Shared utility functions

- **Improved Documentation**
  - Comprehensive README.md with quick start guide
  - CHANGELOG.md for version tracking
  - docs/operations/ - Operational guides
  - docs/architecture/ - System design docs
  - docs/development/ - Developer contribution guide

- **Artifact Management**
  - `artifacts/` directory for generated files (gitignored)
  - Cleaner repo with build logs excluded from version control
  - .gitkeep files to preserve directory structure

### Changed

- **Script Locations** (all functionality preserved)
  - `scripts/build-vm.sh` → `src/provisioning/build-vm.sh`
  - `scripts/setup-crd.sh` → `src/provisioning/setup-crd.sh`
  - `scripts/verify-security.sh` → `src/security/verify-security.sh`
  - `vm-scripts/install_monitoring.sh` → `src/monitoring/install-monitoring.sh`
  - See README.md for complete mapping

- **Configuration Organization**
  - `config/users/` - User VM configurations (unchanged)
  - `config/project/` - Project-level settings (new)
  - `config/schema/` - Validation schemas (new)

- **Documentation Structure**
  - `docs/` split into architecture/operations/development
  - Better organization for different audiences

### Fixed

- **IAP Authorization** - Engineers can now use IAP tunneling without permission errors
- **Script Duplication** - Removed duplicate scripts from `golden-images/v3-gnome/`
- **Unclear Responsibilities** - Each directory now has one clear purpose

### Removed

- **Duplication** - Eliminated all duplicate scripts and files
- **Confusion** - Removed ambiguous directory structures
- **Clutter** - Moved build artifacts and generated files to gitignored `artifacts/`

---

## [1.0] - 2024-11-26

### Initial Release

- Native IAM security architecture (no sudo access for engineers)
- Automated VM provisioning with `build-vm.sh`
- Chrome Remote Desktop support
- Activity monitoring and auto-shutdown (30min idle)
- Git statistics tracking (hourly LOC counting)
- Daily backups with 7-day retention
- Security verification with 13-point audit
- Onboarding email generation
- Golden image support (GNOME desktop)

### Security Features

- Project-level `enable-oslogin-sudo=FALSE` enforcement
- CustomEngineerRole with limited permissions
- OS Login integration without sudo
- Comprehensive security verification

### Monitoring Features

- Activity daemon tracking file changes and CPU
- Git statistics for productivity metrics
- GCS log synchronization
- Automated backups to local and cloud storage

---

## Migration Guide: v1.0 → v2.0

### No Workflow Changes Required!

All scripts work the same way, they're just in new locations. You have two options:

**Option 1: Use New Repo (Recommended)**
```bash
cd /path/to/GCP-engg-golden-VM
./src/provisioning/build-vm.sh config/users/engineer.yaml
```

**Option 2: Keep Using Old Repo**
```bash
cd /path/to/GCP-Engg_VM-v2-sudo-first
./scripts/build-vm.sh config/users/engineer.yaml
```

Both work! The new repo is cleaner and better organized for long-term maintenance.

### What Stays The Same

- ✅ All command-line arguments
- ✅ Configuration file format
- ✅ IAM permissions
- ✅ VM behavior and features
- ✅ Security model
- ✅ Monitoring and backups

### What's Different

- ✅ Directory structure (much cleaner!)
- ✅ Script paths (organized by purpose)
- ✅ Documentation (better organized)
- ✅ IAP support (newly added)

---

**For questions or issues, contact:** scott@brightfox.ai
