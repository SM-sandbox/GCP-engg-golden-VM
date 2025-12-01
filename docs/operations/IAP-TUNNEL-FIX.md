# IAP Tunnel Authorization Fix

**Date:** December 1, 2025  
**Issue:** Error 4033 - "not authorized" when using IAP for TCP forwarding

## Root Cause

Engineers were missing the `roles/iap.tunnelResourceAccessor` IAM role, which is required when using the `--tunnel-through-iap` flag with gcloud SSH commands.

The `scripts/setup-crd.sh` script uses IAP tunneling but the role was not being granted during VM provisioning.

## Error Message

```text
Error while connecting [4033: 'not authorized']
= You do not have the correct IAM permissions to use IAP for TCP forwarding.
```

## Resolution

### 1. Fixed Existing Users

Granted IAP Tunnel Resource Accessor role to all current engineers:

```bash
gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:akash@brightfox.ai" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:ankush@brightfox.ai" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:jerry@brightfox.ai" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:vm1.gcp@brightfox.ai" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding gcp-engg-vm \
  --member="user:vm2.gcp@brightfox.ai" \
  --role="roles/iap.tunnelResourceAccessor"
```

### 2. Updated Build Script

Modified `scripts/build-vm.sh` to automatically grant this role during VM provisioning (Step 3 - Permission 5).

## Complete IAM Permissions for Engineers

After this fix, engineers now have:

1. ✅ `projects/gcp-engg-vm/roles/CustomEngineerRole` - Start/Stop/Reset VMs
2. ✅ `roles/compute.osLogin` - SSH access
3. ✅ `roles/compute.instanceAdmin.v1` - Temporary for CRD setup
4. ✅ `roles/iam.serviceAccountUser` - Use VM service account
5. ✅ **`roles/iap.tunnelResourceAccessor`** - IAP TCP forwarding (NEW)

## Testing

Verify engineer has IAP access:

```bash
gcloud projects get-iam-policy gcp-engg-vm \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  --filter="bindings.members:user:<engineer-email> AND bindings.role:iap"
```

Should show `roles/iap.tunnelResourceAccessor` for the user.

## Impact

- ✅ Engineers can now connect using IAP tunneling
- ✅ `setup-crd.sh` script will work without authorization errors
- ✅ Future VMs will automatically include this permission
- ✅ More secure than using direct external IP SSH

## Related Files

- `scripts/build-vm.sh` - Lines 207-213 (IAP permission grant)
- `scripts/setup-crd.sh` - Lines 65, 83 (Uses --tunnel-through-iap)
