# Security Audit Checklist

**Purpose:** Periodic verification that all engineer VMs maintain proper security posture.

**Frequency:** Run monthly or after any IAM policy changes.

---

## Quick Audit - All Engineers

Run this command to check all active engineers for `instanceAdmin.v1`:

```bash
# Check IAM for all engineers
gcloud projects get-iam-policy gcp-engg-vm \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  | grep -E "(akash|ankush|jerry)" \
  | grep "instanceAdmin"
```

**Expected Result:** No output (no engineers should have `instanceAdmin.v1`)

**If found:**
```bash
# Remove the role immediately
gcloud projects remove-iam-policy-binding gcp-engg-vm \
  --member="user:<engineer>@brightfox.ai" \
  --role="roles/compute.instanceAdmin.v1"
```

---

## Full Security Audit - Per Engineer

For each engineer, run the full verification script:

```bash
./scripts/verify-security.sh <username> <vm-name> gcp-engg-vm us-east1-b
```

**Example:**
```bash
./scripts/verify-security.sh akash dev-akash-vm-002 gcp-engg-vm us-east1-b
./scripts/verify-security.sh ankush dev-ankush-vm-002 gcp-engg-vm us-east1-b
./scripts/verify-security.sh jerry dev-jerry-vm-002 gcp-engg-vm us-east1-b
```

**All 6 tests must pass:**
1. ✅ IAM Roles - No instanceAdmin.v1
2. ✅ Project metadata correct
3. ✅ No problematic sudoers entries
4. ✅ No OS Login sudo file
5. ✅ Static IP assigned
6. ✅ SSH connectivity works

---

## Manual Sudo Check (If VM is Running)

If you want to manually verify an engineer cannot use sudo:

```bash
# SSH into the VM as admin
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b

# Try to run sudo as the engineer
sudo -u <username>_brightfox_ai sudo -n ls /root 2>&1
```

**Expected Output:**
```
sudo: a password is required
```

**If no error:** SECURITY BREACH - Engineer has sudo access. Run full audit immediately.

---

## Audit Log

Keep a record of security audits:

| Date | Auditor | Engineers Checked | Issues Found | Resolution |
|------|---------|-------------------|--------------|------------|
| 2025-11-29 | Scott | Akash, Ankush, Jerry | Ankush & Akash had instanceAdmin.v1 | Removed role, deleted sudo files, fixed setup-crd.sh |
| | | | | |

---

## Red Flags - Immediate Action Required

🚨 **If you see any of these, stop all onboarding and investigate:**

1. **Engineer has `instanceAdmin.v1`**
   - Auto-grants sudo via OS Login
   - Remove immediately

2. **OS Login sudo file exists: `/var/google-sudoers.d/<username>_brightfox_ai`**
   - Engineer has full sudo access
   - Delete file and check IAM roles

3. **Engineer in `google-sudoers` group**
   - Should only be temporary during CRD setup
   - Remove from group: `sudo gpasswd -d <username> google-sudoers`

4. **Project metadata not set: `enable-oslogin-sudo=FALSE`**
   - All new OS Login users will get sudo
   - Set immediately: See `scripts/build-vm.sh` for command

5. **Engineer can read monitoring code**
   - Can see activity tracking, billing info, GCS buckets
   - Fix permissions: `/opt/dev-monitoring/` must be 700 root:root

---

## Emergency Response

**If you discover an active security breach:**

1. **Immediately remove sudo access:**
   ```bash
   # Remove IAM role if present
   gcloud projects remove-iam-policy-binding gcp-engg-vm \
     --member="user:<engineer>@brightfox.ai" \
     --role="roles/compute.instanceAdmin.v1"
   
   # SSH into VM and remove sudo file
   gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b \
     --command="sudo rm -f /var/google-sudoers.d/<username>_brightfox_ai"
   ```

2. **Verify removal:**
   ```bash
   ./scripts/verify-security.sh <username> <vm-name> gcp-engg-vm us-east1-b
   ```

3. **Audit what they accessed:**
   - Check `/var/log/auth.log` for sudo commands
   - Check `/var/log/dev-activity/` for their actions
   - Review GCS bucket access logs

4. **Document the incident** in the Audit Log above

---

## Prevention

✅ **Always use the scripts:**
- `./scripts/build-vm.sh` - Sets up VMs correctly
- `./scripts/setup-crd.sh` - Has IAM role check
- `./scripts/verify-security.sh` - Validates security

✅ **Never manually grant IAM roles** - use the build script

✅ **Run monthly audits** - catch drift before it becomes a problem

✅ **Review GCP Console IAM page** - look for any manual grants outside automation
