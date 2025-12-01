# The "Nightmare on Elm Street": A Chronicle of Permissions, ADC, and Sudo

## 1. The Core Conflict: Security vs. Usability

The central challenge of this project was balancing two opposing requirements:
1.  **Zero Sudo Access:** The engineer must NOT have `sudo` access to prevent tampering with monitoring.
2.  **User-Level Config:** The engineer needs to configure Chrome Remote Desktop (CRD) and VS Code, which typically require system-level changes (installing packages, modifying `/etc`).

## 2. The Chicken & Egg Problem (OS Login)

We use **Google Cloud OS Login** for SSH access. This introduces a unique "Chicken & Egg" problem:
*   **The Problem:** The user account (e.g., `akash_brightfox_ai`) **does not exist** on the VM until the user logs in for the first time.
*   **The Consequence:** We cannot pre-configure permissions (like `chown`ing log directories) or run commands as the user (e.g., disabling lock screens) during the build process because the user is unknown to the OS.
*   **The Solution:**
    *   **Golden Image:** We build the VM with all software installed but *no users*.
    *   **Lazy Provisioning:** Monitoring scripts handle "missing users" gracefully (logging as root until the user appears).
    *   **Post-Login Setup:** We moved user-specific setup (Lock Screen disable) to the `setup-crd.sh` script, which runs *after* the user is established.

## 3. The "Sudo Dance" (Chrome Remote Desktop)

Chrome Remote Desktop (CRD) registration requires `sudo` to restart services and modify config.
*   **The Dilemma:** If we give the user `sudo` to register CRD, they might keep it (security risk). If we don't, they can't work.
*   **The Solution: `setup-crd.sh`**
    1.  Admin runs the script.
    2.  Script SSHs into the VM.
    3.  **Grants** temporary `sudo` to the user via `google-sudoers` group.
    4.  **Runs** the registration command as the user.
    5.  **Revokes** `sudo` immediately.
    6.  **Verifies** revocation.

## 4. The ADC (Application Default Credentials) Nightmare

We initially faced issues where `gcloud` commands inside the VM would fail or use the wrong identity.
*   **The Trap:** Engineers running `gcloud auth login` or `gcloud auth application-default login` would overwrite the VM's Service Account identity with their own User Credentials.
*   **The Risk:** If the user has broad IAM permissions (e.g., Owner), their local scripts could delete production resources. If they have no permissions, they can't access GCS buckets the VM *should* verify.
*   **The Fix:**
    *   We force the VM to use its **Attached Service Account** for monitoring operations (`gsutil rsync`).
    *   We restrict the Service Account's IAM roles to *only* what is needed (Logging, Storage Object Creator).
    *   We verify `enable-oslogin-sudo=FALSE` in project metadata to ensure no accidental sudo inheritance.

## 5. The "Golden Image" Workflow

To solve the build time constraints (< 5 mins), we moved from "Install-on-Boot" to "Immutable Infrastructure":
1.  **Build Base VM:** Install Chrome, Windsurf, Drivers, Monitoring.
2.  **Sanitize:** Ensure no user keys/logs are present.
3.  **Capture Image:** `gcp-engg-golden-v1`.
4.  **Deploy:** Create new VMs from this image. Apps are pre-installed; only "User" logic runs.

## 6. Final Architecture Status

*   **Security:** 100% Native IAM. No `sudo` for engineers.
*   **Monitoring:** Root-owned daemon, user-presence detection (X11 Idle), Screenshot recording (Scrot).
*   **Reliability:** Static IPs, Hourly Git Stats, Daily GCS Sync.
*   **Recovery:** Daily Local Backups + Cloud Sync.
