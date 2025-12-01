# VM Configuration "Cafeteria" System

## Overview

This directory contains YAML configuration files for provisioning VMs. Each user can have multiple VM configurations with different specs and permissions.

## Configuration Types

### Small VMs (VM-001 series)
- **Machine:** n2-standard-2 (2 vCPU, 8GB RAM)
- **Disk:** 50GB
- **Use Case:** Basic development, testing, light workloads
- **Cost:** ~$60/month if running 24/7

### Standard VMs (VM-002 series)  
- **Machine:** n2-standard-4 (4 vCPU, 16GB RAM)
- **Disk:** 100GB
- **Use Case:** Regular development, moderate workloads
- **Cost:** ~$120/month if running 24/7

### Large VMs (VM-003 series)
- **Machine:** n2-standard-8 (8 vCPU, 32GB RAM)
- **Disk:** 200GB
- **Use Case:** Heavy workloads, ML/AI training, data processing
- **Cost:** ~$240/month if running 24/7

## File Naming Convention

`{username}-{size}.yaml`

**Examples:**
- `akash.yaml` - Default/standard config for Akash
- `akash-small.yaml` - Small VM config for Akash
- `akash-standard.yaml` - Standard VM config for Akash  
- `akash-large.yaml` - Large VM config for Akash

## VM Naming Convention

VMs are named: `dev-{username}-vm-{XXX}`

Where XXX is a 3-digit number (001, 002, 003, etc.)

**Examples:**
- `dev-akash-vm-001` - Akash's first/small VM
- `dev-akash-vm-002` - Akash's second/standard VM
- `dev-akash-vm-003` - Akash's third/large VM

## Usage

### Building a VM

```bash
# Build default/standard VM for Akash
./scripts/build-vm.sh config/users/akash.yaml

# Build small VM for Akash
./scripts/build-vm.sh config/users/akash-small.yaml

# Build large VM for Akash
./scripts/build-vm.sh config/users/akash-large.yaml
```

### Creating New Configurations

1. Copy an existing YAML file
2. Update the values:
   - `vm.name` - Must be unique (dev-{username}-vm-XXX)
   - `vm.machine_type` - VM size
   - `vm.disk_size_gb` - Disk size
   - `vm.description` - What it's for
3. Save as `{username}-{config-name}.yaml`
4. Run build script

## Security

**All VMs have the same security model:**
- ✅ Engineer has NO sudo access
- ✅ Monitoring directories secured (700)
- ✅ Can start/stop their own VM
- ✅ Can SSH to their own VM
- ❌ Cannot see monitoring code
- ❌ Cannot access root

**Only Scott (admin) has sudo/root access to all VMs**

## Multiple VMs Per User

Engineers can have multiple VMs running simultaneously:
- Small VM for testing
- Standard VM for daily work  
- Large VM for heavy processing (spin up when needed)

Each VM:
- Has a unique name (vm-001, vm-002, etc.)
- Has its own static IP
- Is independently controlled (start/stop)
- Has the same user permissions

## Example: Akash's VM Fleet

```yaml
# akash-small.yaml → dev-akash-vm-001 (small, always on)
# akash-standard.yaml → dev-akash-vm-002 (standard, daily use)
# akash-large.yaml → dev-akash-vm-003 (large, on-demand)
```

Akash can start/stop each independently based on his needs.
