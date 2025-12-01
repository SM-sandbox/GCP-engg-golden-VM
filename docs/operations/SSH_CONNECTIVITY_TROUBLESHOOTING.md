# SSH Connectivity Troubleshooting Guide

## Issue: IAP Tunnel Error "failed to connect to backend"

### Error Message
```
ERROR: [0] Error during local connection to [stdin]: Error while connecting 
[4003: 'failed to connect to backend']. (Failed to connect to port 22)
Connection closed by UNKNOWN port 65535
```

---

## Root Cause Analysis

### Primary Issue: VM Was Stopped
The VM `dev-akash-gnome-vm-001` was in **TERMINATED** state when the connection attempt was made.

**Symptoms:**
- Error message: "External IP address was not found; defaulting to using IAP tunneling"
- IAP connection failed: "failed to connect to backend"
- Connection closed by UNKNOWN port

**Diagnosis:**
```bash
gcloud compute instances describe dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --format="get(status)"
# Output: TERMINATED
```

### Secondary Issue: Missing IAP Firewall Rule
While the immediate problem was the stopped VM, the project **lacks an IAP firewall rule**, which can cause similar connectivity issues when:
1. The VM has no external IP assigned
2. The connection must use IAP TCP forwarding

**Current Firewall Rules:**
```
NAME                    SOURCE_RANGES  ALLOW                         TARGET_TAGS
default-allow-icmp      0.0.0.0/0      icmp
default-allow-internal  10.128.0.0/9   tcp:0-65535,udp:0-65535,icmp
default-allow-rdp       0.0.0.0/0      tcp:3389
default-allow-ssh       0.0.0.0/0      tcp:22
```

**Missing:** Firewall rule for IAP IP range `35.235.240.0/20`

---

## Solution

### Immediate Fix: Start the VM
```bash
gcloud compute instances start dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm \
  --zone=us-east1-b
```

**Wait 30-60 seconds for SSH to become available**, then test:
```bash
gcloud compute ssh akash_brightfox_ai@dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm \
  --zone=us-east1-b
```

### Long-term Fix: Add IAP Firewall Rule
Create a firewall rule to allow IAP TCP forwarding:

```bash
gcloud compute firewall-rules create allow-ssh-from-iap \
  --project=gcp-engg-vm \
  --network=default \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=dev-vm \
  --description="Allow SSH via IAP for Identity-Aware Proxy"
```

**Why this matters:**
- If a VM loses its external IP or is configured without one
- IAP tunneling will be the fallback connection method
- Without this rule, IAP connections will fail with "backend connection error"

---

## Troubleshooting Workflow

### Step 1: Check VM Status
```bash
gcloud compute instances describe <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --format="value(status)"
```

**Expected:** `RUNNING`  
**If TERMINATED:** Start the VM and wait 30-60 seconds

### Step 2: Check for External IP
```bash
gcloud compute instances describe <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

**If empty:** VM has no external IP and will use IAP tunneling

### Step 3: Verify SSH Service
```bash
# Check if port 22 is accessible (requires VM running + external IP)
nc -zv <external-ip> 22 -w 5

# Or check via serial console
gcloud compute instances get-serial-port-output <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --port=1 | grep -i "ssh.service"
```

**Expected:** "Started OpenBSD Secure Shell server"

### Step 4: Check IAP Firewall Rules
```bash
gcloud compute firewall-rules list \
  --project=gcp-engg-vm \
  --filter="sourceRanges:35.235.240.0/20" \
  --format="table(name,sourceRanges,allowed,targetTags)"
```

**Expected:** At least one rule allowing tcp:22 from 35.235.240.0/20

### Step 5: Test Connection
```bash
# Test with direct SSH
gcloud compute ssh <username>@<vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --command="echo 'Connection successful'"

# If failing, use troubleshoot mode
gcloud compute ssh <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --troubleshoot
```

---

## Common Error Patterns

### Pattern 1: VM Stopped/Terminated
**Error:** "failed to connect to backend" + "UNKNOWN port 65535"  
**Cause:** VM not running  
**Fix:** Start the VM

### Pattern 2: No External IP + No IAP Firewall
**Error:** "failed to connect to backend" (after defaulting to IAP)  
**Cause:** Missing IAP firewall rule  
**Fix:** Add allow-ssh-from-iap firewall rule

### Pattern 3: SSH Service Not Running
**Error:** "Connection refused" on port 22  
**Cause:** SSH daemon crashed or disabled  
**Fix:** Check serial console logs, restart ssh.service

### Pattern 4: OS Login Issues
**Error:** "Permission denied (publickey)"  
**Cause:** OS Login not enabled or user lacks roles  
**Fix:** 
```bash
# Check VM metadata
gcloud compute instances describe <vm-name> \
  --format="get(metadata.items[enable-oslogin])"

# Check user roles
gcloud projects get-iam-policy gcp-engg-vm \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:<email>"
```

---

## Prevention

### In VM Build Scripts
Add IAP firewall rule creation to `build-vm.sh`:

```bash
# After creating VM, ensure IAP firewall exists
gcloud compute firewall-rules create allow-ssh-from-iap \
  --project=$PROJECT \
  --network=default \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=dev-vm \
  --quiet || echo "✅ IAP firewall rule already exists"
```

### In Monitoring
- Monitor VM status (RUNNING vs TERMINATED)
- Alert when VMs are stopped unexpectedly
- Check SSH connectivity as part of health checks

### Documentation
- Update README with IAP setup instructions
- Add "VM not starting?" section with common causes
- Document auto-shutdown behavior (30-min idle timeout)

---

## Related Documentation

- [IAP TCP Forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [OS Login Troubleshooting](https://cloud.google.com/compute/docs/oslogin/set-up-oslogin#troubleshooting)
- [VM Startup Scripts](https://cloud.google.com/compute/docs/instances/startup-scripts/linux)

---

## Quick Reference Commands

```bash
# Start VM
gcloud compute instances start <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# Stop VM
gcloud compute instances stop <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# Check status
gcloud compute instances describe <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# SSH with troubleshooting
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b --troubleshoot

# Check serial console (last 100 lines)
gcloud compute instances get-serial-port-output <vm-name> \
  --project=gcp-engg-vm \
  --zone=us-east1-b \
  --port=1 | tail -100
```

---

**Last Updated:** December 1, 2025  
**Verified Against:** VM `dev-akash-gnome-vm-001` (Ubuntu 22.04, GNOME desktop)
