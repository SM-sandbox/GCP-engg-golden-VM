# SSH Connectivity Incident Report
**Date:** December 1, 2025  
**VM:** `dev-akash-gnome-vm-001`  
**Project:** `gcp-engg-vm`  
**Zone:** `us-east1-b`

---

## Incident Summary

Engineer Akash reported SSH connectivity failure with error:
```
ERROR: [0] Error during local connection to [stdin]: Error while connecting 
[4003: 'failed to connect to backend']. (Failed to connect to port 22)
```

---

## Root Cause

**Primary Issue:** VM was in `TERMINATED` state (stopped)

The error message "External IP address was not found; defaulting to using IAP tunneling" was misleading—it appeared because the gcloud SDK couldn't retrieve the external IP of a stopped VM, not because the IP was missing from the configuration.

**Secondary Issue:** Missing IAP firewall rule

While not the immediate cause, the project lacked a firewall rule for IAP's IP range (`35.235.240.0/20`), which could cause similar failures if:
- A VM has no external IP configured
- IAP tunneling is required for connectivity

---

## Resolution

### Immediate Fix
1. ✅ Started the VM: `gcloud compute instances start dev-akash-gnome-vm-001`
2. ✅ Verified SSH connectivity after 30-second boot period
3. ✅ External IP assigned: `34.26.86.113`

### Long-term Fix
1. ✅ Created IAP firewall rule `allow-ssh-from-iap`
   - Source range: `35.235.240.0/20` (Google's IAP service IPs)
   - Target: VMs with tag `dev-vm`
   - Protocol: tcp:22

2. ✅ Updated `build-vm.sh` to ensure IAP firewall exists as Step 1
   - Prevents future IAP connectivity issues
   - Idempotent (safe to run multiple times)

3. ✅ Created comprehensive troubleshooting guide
   - Location: `docs/operations/SSH_CONNECTIVITY_TROUBLESHOOTING.md`
   - Includes diagnostic workflow, common patterns, prevention strategies

---

## Timeline

| Time | Event |
|------|-------|
| ~11:00 EST | VM auto-shutdown due to 30-min idle timeout |
| 12:00 EST | Engineer Akash attempted SSH connection |
| 12:00 EST | Error reported: "failed to connect to backend" |
| 12:01 EST | Investigation started |
| 12:01 EST | Identified VM in TERMINATED state |
| 12:02 EST | Started VM, obtained external IP |
| 12:02 EST | Discovered missing IAP firewall rule |
| 12:03 EST | Created IAP firewall rule |
| 12:03 EST | Updated build scripts and documentation |
| 12:03 EST | Verified SSH connectivity restored |

---

## Key Learnings

### What Went Well
- Quick diagnosis using `gcloud compute instances describe`
- Serial console logs confirmed SSH daemon was configured correctly
- Systematic troubleshooting workflow

### What Could Be Improved
1. **VM Status Monitoring**: Engineers should be notified when VMs auto-shutdown
2. **Startup Documentation**: README should mention VMs may be stopped and how to start them
3. **IAP Configuration**: Should have been included in initial infrastructure setup

### Preventive Measures Implemented
1. IAP firewall rule now created automatically during VM provisioning
2. Comprehensive troubleshooting guide for future incidents
3. Updated build scripts to include IAP connectivity checks

---

## Action Items

- [x] Fix immediate issue (start VM)
- [x] Add IAP firewall rule
- [x] Update build scripts
- [x] Create troubleshooting documentation
- [ ] Consider adding VM status to monitoring dashboard
- [ ] Update onboarding email to mention auto-shutdown behavior
- [ ] Add "Quick Start" section to README with VM start/stop commands

---

## Commands Used

```bash
# Diagnosis
gcloud compute instances describe dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm --zone=us-east1-b --format="get(status)"

# Resolution
gcloud compute instances start dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm --zone=us-east1-b

# Prevention
gcloud compute firewall-rules create allow-ssh-from-iap \
  --project=gcp-engg-vm \
  --network=default \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --target-tags=dev-vm

# Verification
gcloud compute ssh akash_brightfox_ai@dev-akash-gnome-vm-001 \
  --project=gcp-engg-vm --zone=us-east1-b
```

---

## Related Files Modified

1. `/docs/operations/SSH_CONNECTIVITY_TROUBLESHOOTING.md` - New comprehensive guide
2. `/src/provisioning/build-vm.sh` - Added IAP firewall as Step 1
3. `INCIDENT_REPORT_2025-12-01.md` - This report

---

**Status:** ✅ RESOLVED  
**Impact:** Minimal (single engineer, ~3 minutes downtime)  
**Likelihood of Recurrence:** Low (preventive measures in place)
