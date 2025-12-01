# Onboarding Email for {{FIRST_NAME}}

**To:** {{USER_EMAIL}}
**From:** {{ADMIN_EMAIL}}
**Subject:** 🚀 Your BrightFox Developer Workstation is Ready!

---

Hi {{FIRST_NAME}},

Your personal cloud development workstation is now set up and ready to go! This is a powerful Ubuntu desktop in the cloud - think of it as your own dedicated computer that you access through your browser.

**Important:** Your workstation auto-shuts down after 30 minutes of inactivity to save costs, so you'll need to start it before connecting each day.

## 🔐 Your Workstation Details

**VM Name:** {{VM_NAME}}
**Static IP:** {{STATIC_IP}}
**Access URL:** https://remotedesktop.google.com/
**Your Email:** {{USER_EMAIL}}

## 🚀 First Time Setup (Takes ~15 minutes)

### Step 1: Authenticate with Google Cloud (IMPORTANT - Do This First!)
Open your **local Terminal** (on your Mac/PC, not the VM) and run:

```bash
gcloud auth login --no-launch-browser
```

Follow the prompts:
1. Copy the URL and open it in your browser
2. Sign in with `{{USER_EMAIL}}`
3. Copy the verification code
4. Paste it back into the terminal

### Step 2: Start Your Workstation
Still in your local Terminal, run:

```bash
gcloud compute instances start {{VM_NAME}} --project={{PROJECT_ID}} --zone={{ZONE}}
```

Wait about 30 seconds for it to start.

### Step 3: Access Chrome Remote Desktop

**Important: You must log in with Scott (via screen share or in person) for this step.** This is a one-time security requirement to authorize your new device.

1. Go to https://remotedesktop.google.com/
2. Sign in with your BrightFox Google account (`{{USER_EMAIL}}`)
3. **Wait for Scott** to authorize the device
4. Once authorized, you should see your workstation: **{{VM_NAME}}**
5. Click on it to connect

### Step 4: Create Your PIN
- You'll be asked to create a 6-digit PIN (example: `123456`)
- **Write this down** - you'll need it every time you connect
- This PIN is only for you, we don't have access to it

### Step 5: Authenticate with Google Cloud (on the VM)
Once you're connected to the desktop, open Terminal **on the VM** and run:

```bash
gcloud auth application-default login --no-launch-browser
```

Follow the prompts:
1. Copy the URL and open it in your browser
2. Sign in with your BrightFox account
3. Copy the verification code
4. Paste it back into the terminal

**Why this matters:** This authentication lasts 90 days and allows you to use cloud storage and other features without constant re-authentication.

### Step 6: Set Up Git
Still in Terminal, run these commands (one at a time):

```bash
git config --global user.name "{{FULL_NAME}}"
git config --global user.email "{{USER_EMAIL}}"
```

### Step 7: Generate SSH Key for GitHub
```bash
# Create SSH key
ssh-keygen -t ed25519 -C "{{USER_EMAIL}}"

# Press Enter 3 times (accept defaults, no passphrase)

# Copy your public key
cat ~/.ssh/id_ed25519.pub
```

Then:
1. Go to https://github.com/settings/keys
2. Click "New SSH Key"
3. Paste your key
4. Title it "BrightFox Workstation"
5. Click "Add SSH Key"

### Step 8: Clone Your First Project
```bash
cd ~/projects
git clone git@github.com:BrightFoxAI/[repository-name].git
cd [repository-name]
windsurf .
```

**That's it! You're ready to code!** 🎉

---

## 📱 Daily Access (Every Day After Setup)

### Quick Start (if VM is already running):
1. Go to https://remotedesktop.google.com/
2. Click on **{{VM_NAME}}**
3. Enter your PIN
4. Start working!

### If VM is shut down (after 30 min idle):
1. Open your local Terminal
2. Run: `gcloud compute instances start {{VM_NAME}} --project={{PROJECT_ID}} --zone={{ZONE}}`
3. Wait 30 seconds
4. Then go to https://remotedesktop.google.com/

**Tip:** Your files persist forever, even when the VM shuts down. Nothing is lost!

---

## 💡 What's Already Installed

- **Windsurf IDE** - Your code editor (use your own license)
- **Google Chrome** - Web browser
- **Python 3** - `python3 --version`
- **Node.js** - `node --version`
- **Git** - `git --version`
- **Docker** - `docker --version`
- **All cloud SDKs** - gcloud, gh, az, azd

---

## 🚀 Alternative Access: SSH + Windsurf (Optional)

If you experience latency issues with Chrome Remote Desktop, you can access your VM via SSH and use Windsurf locally.

**Benefits:**
- Better performance (less latency)
- All code stays on the VM (secure)
- Can switch back to Chrome Remote Desktop anytime

**Setup (One-time):**

1. **Add VM to your local SSH config** (on your Mac/PC):

Create or edit `~/.ssh/config` and add:

```ssh
Host {{VM_NAME}}-ssh
    HostName {{STATIC_IP}}
    User {{USERNAME}}
    IdentityFile ~/.ssh/id_ed25519
```

2. **In Windsurf** (on your local machine):
   - Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows)
   - Type "Remote-SSH: Connect to Host"
   - Select `{{VM_NAME}}-ssh`
   - Windsurf opens connected to the VM!

3. **Open your project**:
   - File → Open Folder
   - Navigate to `/home/{{USERNAME}}/projects/[repo-name]`
   - All work happens on the VM, only UI on your machine

**Daily Use:**
- Start VM: `gcloud compute instances start {{VM_NAME}} --project={{PROJECT_ID}} --zone={{ZONE}}`
- Connect Windsurf via Remote-SSH
- Code normally - everything syncs to VM

---

## 🆘 Troubleshooting

**Can't see your workstation on Chrome Remote Desktop?**
- The VM is probably shut down (auto-shuts after 30 min idle)
- Start it first: `gcloud compute instances start {{VM_NAME}} --project={{PROJECT_ID}} --zone={{ZONE}}`
- Wait 30 seconds, then refresh the page
- Make sure you're signed in with `{{USER_EMAIL}}`
- Contact Scott if it still doesn't appear after starting

**Forgot your PIN?**
- Contact Scott to reset it

**Connection is slow?**
- Check your internet connection
- Try using a wired connection instead of WiFi

---

## 📞 Need Help?

- **Technical issues:** Contact Scott
- **VM not responding:** Contact Scott
- **Forgot a command:** See the Quick Checklist below

---

## ✅ Quick Checklist

- [ ] Authenticated gcloud CLI on your local machine
- [ ] Started the VM
- [ ] Connected to Chrome Remote Desktop
- [ ] Created PIN
- [ ] Authenticated with gcloud on the VM (ADC)
- [ ] Configured Git
- [ ] Generated and added SSH key to GitHub
- [ ] Cloned at least one repository
- [ ] Opened a project in Windsurf

Once you've checked all these boxes, you're fully onboarded! 🦊

---

## 📝 Important Notes

- Your workstation **auto-shuts down after 30 minutes of inactivity** to save costs
- Everything in your home folder (`/home/{{USERNAME}}/`) **persists forever** (even when shut down)
- You have full control to install anything you need (using `sudo` in Terminal if needed)
- Your work auto-saves, but still commit to Git regularly!
- To start VM: `gcloud compute instances start {{VM_NAME}} --project={{PROJECT_ID}} --zone={{ZONE}}`

---

Welcome to BrightFox! Happy coding! 🚀

**— Scott**

---

*P.S. Your workstation has a static IP ({{STATIC_IP}}) which means you can use it for GitHub SSH key whitelisting if needed. Let me know if you want help setting that up.*
