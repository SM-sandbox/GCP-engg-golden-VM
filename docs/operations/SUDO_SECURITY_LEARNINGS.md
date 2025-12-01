# 🛡️ Sudo Security & Chrome Remote Desktop: Learnings & Architecture

## 🎯 Objective
Provision development VMs for engineers that allow:
1.  **Remote Desktop Access** (Chrome Remote Desktop).
2.  **VM Control** (Start/Stop/Reset).
3.  **Zero Sudo Access** (Strict security requirement).

## 🚫 The "Sudo Problem" & Failures

### Attempt 1: The "Monitoring" Approach (FAILED)
*   **Strategy**: Grant standard `compute.instanceAdmin.v1` role + run a script to delete sudo files.
*   **Failure Point 1 (Implicit Access)**: Google's `instanceAdmin.v1` role is interpreted by the metadata server as "Owner". OS Login *automatically* creates a sudoers entry (`/var/google-sudoers.d/<user>`) for any user with this role.
*   **Failure Point 2 (Race Conditions)**: The monitoring service was `Type=oneshot`, running only at boot. It missed files created *after* login. Even if looped, there is a window of vulnerability.
*   **Result**: Engineer had sudo access (or regained it easily).

### Attempt 2: Project Metadata (FAILED)
*   **Strategy**: Set `enable-oslogin-sudo=FALSE`.
*   **Failure Point**: This metadata is often overridden by instance-level settings or ignored if the user has "Owner" level IAM permissions. It was insufficient to block the `instanceAdmin.v1` grant.

---

## ✅ The Solution: Native IAM Architecture

We solved the problem by strictly defining IAM roles instead of fighting against them with scripts.

### 1. The "Custom Engineer" Role
We created a specific IAM role (`CustomEngineerRole`) that grants **only** what is needed:
*   `compute.instances.start`
*   `compute.instances.stop`
*   `compute.instances.reset`
*   `compute.instances.get`
*   `compute.projects.get`

### 2. The IAM Composition
The engineer is granted EXACTLY two roles:
1.  **`roles/compute.osLogin`**: Allows SSH access (without sudo).
2.  **`CustomEngineerRole`**: Allows VM control.

**Crucially**: We REMOVED `roles/compute.instanceAdmin.v1`.
*   **Result**: Google Cloud knows this user is NOT an admin. It **never creates** the sudoers file. The security is enforced by the platform, not a script.

---

## 🔐 The Chrome Remote Desktop (CRD) Challenge

### The Conflict
1.  **CRD Requirement**: Registering a new host (`chrome-remote-desktop --start-host`) requires **Root/Sudo** permissions to write systemd service files (`/etc/systemd/system/...`).
2.  **Security Requirement**: The Engineer **MUST NOT** have sudo access.

This created a deadlock: The engineer cannot set up their own remote desktop because we successfully secured the machine.

### The Solution: "The Sudo Dance"
We implemented a secure onboarding sequence where the **Admin** facilitates the setup without permanently granting permissions.

**The Sequence:**
1.  **Admin SSH**: Admin logs in (with their sudo privileges).
2.  **Impersonation/Grant**: Admin temporarily grants sudo to the engineer OR runs the command *as* the engineer using `sudo -u`.
3.  **Registration**: The CRD setup command runs using the Engineer's OAuth code.
4.  **Revocation**: Sudo access is immediately revoked (or was never permanently granted if using `sudo -u`).

### Implementation
This logic is codified in `scripts/setup-crd.sh`.

```bash
# Conceptual Logic
sudo usermod -aG google-sudoers <engineer>
sudo -u <engineer> /opt/google/chrome-remote-desktop/start-host --code="<AUTH_CODE>" ...
sudo gpasswd -d <engineer> google-sudoers
```

---

## 📂 System Artifacts

### 1. `scripts/build-vm.sh`
*   **Role**: Provisioning & Security Baseline.
*   **Key Action**: Grants `CustomEngineerRole`, **does NOT** grant `instanceAdmin`.
*   **State**: VM is built, secured, and locked down. Engineer cannot yet use CRD.

### 2. `scripts/setup-crd.sh` (New)
*   **Role**: Onboarding.
*   **Key Action**: Performs the "Sudo Dance" to register CRD.
*   **Input**: VM Name, Username, OAuth Code.
*   **State**: CRD is active. User is secure.

### 3. `scripts/verify-security.sh`
*   **Role**: Validation.
*   **Key Action**: Verifies `sudo -n true` fails, checking the final state.

---

## 🚀 Summary
We moved from a **Reactive** security model (monitor and delete sudo files) to a **Proactive** security model (Native IAM). The complex setup requirements of CRD are handled via a controlled, administrative action during onboarding, ensuring the "Zero Sudo" state is never compromised during normal operation.
