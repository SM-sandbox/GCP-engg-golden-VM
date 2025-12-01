# NoMachine Remote Desktop Setup

NoMachine is an alternative to Chrome Remote Desktop that provides lower latency and full keyboard shortcut support.

## When to Use NoMachine vs Chrome Remote Desktop

| Feature | Chrome Remote Desktop | NoMachine |
|---------|----------------------|-----------|
| **Latency** | Higher (browser-based) | Lower (native protocol) |
| **Keyboard Shortcuts** | Many intercepted by Chrome | All work correctly |
| **Setup Complexity** | Simple (browser only) | Requires client install |
| **Firewall** | Works through existing rules | Requires ports 4000, 4011-4020 |
| **Best For** | Quick access, light use | Heavy development work |

**Recommendation:** Use NoMachine for daily development work. Use CRD for quick access from any browser.

## Administrator Setup

### For Existing VMs

```bash
# 1. Install NoMachine server on the VM
./src/provisioning/install-nomachine.sh <vm-name>

# 2. Configure firewall and tag VM
./src/provisioning/setup-nomachine-firewall.sh <vm-name>
```

### For New VMs (Future Golden Image)

NoMachine will be pre-installed in the golden image. Administrators only need to:

```bash
# Tag VM for NoMachine access
./src/provisioning/setup-nomachine-firewall.sh <vm-name>
```

## Engineer Setup

### Step 1: Download NoMachine Client

Go to: https://www.nomachine.com/download

Download for your operating system:
- **macOS:** NoMachine for macOS
- **Windows:** NoMachine for Windows
- **Linux:** NoMachine for Linux

### Step 2: Install Client

Open the downloaded file and follow the installation wizard.

### Step 3: Connect to VM

1. Open NoMachine application
2. Click **New connection**
3. Enter connection details:
   - **Protocol:** NX
   - **Host:** Your VM's external IP address
   - **Port:** 4000
   - **Name:** Any friendly name (e.g., "My Dev VM")
4. Click **Connect**
5. Login with your VM credentials:
   - **Username:** Your OS Login username (e.g., `akash_brightfox_ai`)
   - **Password:** Your SSH password
6. Select your desktop session (GNOME)

## Troubleshooting

### Connection Timeout

**Symptoms:** "Connection timeout on port 4000"

**Causes:**
1. VM is stopped
2. Firewall rule not applied
3. VM not tagged with `nomachine-enabled`

**Fix:**
```bash
# Check VM status
gcloud compute instances describe <vm-name> --project=gcp-engg-vm --zone=us-east1-b --format="value(status)"

# Check VM tags
gcloud compute instances describe <vm-name> --project=gcp-engg-vm --zone=us-east1-b --format="value(tags.items)"

# Re-run firewall setup if needed
./src/provisioning/setup-nomachine-firewall.sh <vm-name>
```

### Can't Login

**Symptoms:** Username/password rejected

**Causes:**
1. Wrong username format
2. Password not set

**Fix:**
- Use your OS Login username (check with `whoami` via SSH)
- Ensure you have a password set on the VM

### NoMachine Service Not Running

**Symptoms:** Connection refused

**Fix:**
```bash
# SSH to VM and check service
gcloud compute ssh <vm-name> --project=gcp-engg-vm --zone=us-east1-b --command="
sudo systemctl status nxserver
sudo systemctl restart nxserver
"
```

### Slow Performance

**Symptoms:** Laggy mouse/keyboard

**Fix:**
1. In NoMachine client, go to **Settings > Display**
2. Lower the quality setting
3. Disable "Resize remote display" if enabled

## Security Notes

- NoMachine uses ports 4000 and 4011-4020
- Firewall rule only applies to VMs tagged with `nomachine-enabled`
- Authentication uses VM user credentials
- All traffic is encrypted

## Firewall Rule Details

```yaml
Name: allow-nomachine
Network: default
Direction: INGRESS
Priority: 1000
Ports: tcp:4000, tcp:4011-4020
Target Tags: nomachine-enabled
Source: 0.0.0.0/0 (any IP)
```

## Related Documentation

- [Chrome Remote Desktop Setup](CHROME_REMOTE_DESKTOP_SETUP.md)
- [SSH Connectivity Troubleshooting](SSH_CONNECTIVITY_TROUBLESHOOTING.md)
- [VM Onboarding Guide](VM_Onboarding_Guide.md)
