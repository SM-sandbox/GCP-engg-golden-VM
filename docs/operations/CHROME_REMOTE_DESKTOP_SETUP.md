# Chrome Remote Desktop Setup Guide

**Target Audience:** Admins provisioning VMs for Engineers.
**Context:** Engineers (`vm1`, `akash`, `jerry`) do **NOT** have sudo access. This makes standard CRD setup impossible for them to do alone.

## The Protocol

Because the `start-host` command requires `systemd` access (which requires root), the Admin must perform the setup on behalf of the Engineer using a "Sudo Sandwich" technique.

### 1. Engineer Step: Get the Code
The Engineer must generate the OAuth code linked to **their** Google Account.
1.  Visit [https://remotedesktop.google.com/headless](https://remotedesktop.google.com/headless).
2.  Click **Begin** -> **Next** -> **Authorize**.
3.  Copy the command displayed (specifically the `--code="4/0..."` part).
4.  Send this code to the Admin securely (Slack/Teams).

### 2. Admin Step: Register the Host
The Admin (who has root access) must SSH into the VM and execute the registration.

**Variables:**
- `VM_NAME`: e.g., `dev-shm-vm-003`
- `USER`: e.g., `vm1_gcp_brightfox_ai`
- `CODE`: The string provided by the Engineer.
- `PIN`: Default `123456` (Engineer can change later).

**Execution (One-Liner):**
This script grants temporary `NOPASSWD` sudo, runs the registration, and then revokes it immediately.

```bash
# SSH in first
gcloud compute ssh dev-shm-vm-003 --project=gcp-engg-vm --zone=us-east1-b

# Run the sequence (replace variables)
export TARGET_USER="vm1_gcp_brightfox_ai"
export AUTH_CODE="4/0..." 
export VM_NAME="dev-shm-vm-003"

# 1. Grant Sudo
echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/temp-crd-fix

# 2. Register (As User)
echo -e '123456\n123456\n' | sudo -u $TARGET_USER DISPLAY= /opt/google/chrome-remote-desktop/start-host \
    --code="$AUTH_CODE" \
    --redirect-url="https://remotedesktop.google.com/_/oauthredirect" \
    --name="$VM_NAME"

# 3. Revoke Sudo
sudo rm /etc/sudoers.d/temp-crd-fix
```

### 3. Engineer Step: Connect
1.  Visit [https://remotedesktop.google.com/access](https://remotedesktop.google.com/access).
2.  Click the VM name.
3.  Enter the PIN (`123456`).

## Troubleshooting

*   **"sudo: a terminal is required..."**: The user does not have `NOPASSWD` sudo permissions. Ensure Step 1 (Grant Sudo) was successful.
*   **"Invalid Code"**: The code expires quickly. Ask the Engineer for a fresh one.
*   **"Failed to start host"**: Check if the service is already running or if a stale config exists in `~/.config/chrome-remote-desktop/`.
