#!/bin/bash

# Onboarding Email Generator
# Usage: ./scripts/generate-onboarding-email.sh <config-file> <static-ip>

CONFIG_FILE=$1
STATIC_IP=$2

# Parse config (match exact indentation)
USER_EMAIL=$(grep "^  email:" "$CONFIG_FILE" | awk '{print $2}')
USERNAME=$(grep "^  username:" "$CONFIG_FILE" | awk '{print $2}')
FULL_NAME=$(grep "^  full_name:" "$CONFIG_FILE" | cut -d':' -f2 | sed 's/^[[:space:]]*//')
VM_NAME=$(grep "^  name:" "$CONFIG_FILE" | awk '{print $2}')
PROJECT=$(grep "^  project:" "$CONFIG_FILE" | awk '{print $2}')
ZONE=$(grep "^  zone:" "$CONFIG_FILE" | awk '{print $2}')

# Generate Random PIN (Mac/Linux compatible)
RANDOM_PIN=$(python3 -c 'import random; print(random.randint(100000, 999999))')
BUILD_DATE=$(date)

# Generate email
cat << EOF

================================================== 
📧 ONBOARDING EMAIL
================================================== 

To: $USER_EMAIL
Subject: Your Development VM is Ready - $VM_NAME

---

Hi $FULL_NAME,

Your development VM has been provisioned and is ready to use!

🖥️ **VM DETAILS:**
- **Name:** $VM_NAME
- **IP Address:** $STATIC_IP
- **Project:** $PROJECT
- **Zone:** $ZONE
- **Built on:** $BUILD_DATE

---

🔑 **SSH ACCESS (TRY THIS FIRST):**

You can SSH in right now to verify connectivity and use tools like Windsurf.

Run this command:

\`\`\`bash
gcloud compute ssh $USERNAME@$VM_NAME --project=$PROJECT --zone=$ZONE
\`\`\`

**Please confirm that this works.**

---

🖥️ **CHROME REMOTE DESKTOP SETUP:**

**Requires a quick sync with Scott.**

For security reasons, you do not have \`sudo/root\` access on this machine. Registering Chrome Remote Desktop requires sudo, so we need to do this together.

**Action:** Next time you are on a call with Scott, let him know you are ready to set up Remote Desktop. He will handle the registration step with you.

---

🛡️ **SECURITY & PERMISSIONS:**

To keep our environment secure, engineers do not have \`sudo\` access.

*   If you run into permission issues or think you need sudo for a task, please let me know.
*   We can adjust permissions or install tools as needed.

---

🚀 **CAPACITY:**

Let me know if this machine specification is sufficient for your workload.
*   I can spin up a **bigger machine** pretty quickly.
*   I can give you **multiple machines** if you need them.

Just let me know!

Best regards,
Scott

📋 **VM CONTROLS:**

**Start your VM:**
\`\`\`bash
gcloud compute instances start $VM_NAME --project=$PROJECT --zone=$ZONE
\`\`\`

**Stop your VM:**
\`\`\`bash
gcloud compute instances stop $VM_NAME --project=$PROJECT --zone=$ZONE
\`\`\`

**Check VM status:**
\`\`\`bash
gcloud compute instances describe $VM_NAME --project=$PROJECT --zone=$ZONE --format="get(status)"
\`\`\`

---

✅ **Everything is configured and ready to go!**

If you have any issues connecting or using the VM, please let me know.

Best regards,
Scott

---

**Note:** Your VM has been configured with secure access. You have the permissions needed to start/stop your VM and SSH into it. If you need additional software or packages installed, please reach out.

EOF

echo ""
echo "=================================================="
echo ""
echo "📋 Email saved to: onboarding-emails/$VM_NAME-onboarding.txt"

# Save email to file
mkdir -p onboarding-emails
cat << EOF > onboarding-emails/$VM_NAME-onboarding.txt
To: $USER_EMAIL
Subject: Your Development VM is Ready - $VM_NAME

Hi $FULL_NAME,

Your development VM has been provisioned and is ready to use!

🖥️ VM DETAILS:
- Name: $VM_NAME
- IP Address: $STATIC_IP
- Project: $PROJECT
- Zone: $ZONE

🔑 SSH ACCESS (TRY THIS FIRST):

You can SSH in right now to verify connectivity and use tools like Windsurf.

Run this command:

gcloud compute ssh $USERNAME@$VM_NAME --project=$PROJECT --zone=$ZONE

Please confirm that this works.

🖥️ CHROME REMOTE DESKTOP SETUP:

Requires a quick sync with Scott.

For security reasons, you do not have sudo/root access on this machine. Registering Chrome Remote Desktop requires sudo, so we need to do this together.

Action: Next time you are on a call with Scott, let him know you are ready to set up Remote Desktop. He will handle the registration step with you.

🛡️ SECURITY & PERMISSIONS:

To keep our environment secure, engineers do not have sudo access.

*   If you run into permission issues or think you need sudo for a task, please let me know.
*   We can adjust permissions or install tools as needed.

🚀 CAPACITY:

Let me know if this machine specification is sufficient for your workload.
*   I can spin up a bigger machine pretty quickly.
*   I can give you multiple machines if you need them.

Just let me know!

Best regards,
Scott

📋 VM CONTROLS:

Start: gcloud compute instances start $VM_NAME --project=$PROJECT --zone=$ZONE
Stop: gcloud compute instances stop $VM_NAME --project=$PROJECT --zone=$ZONE

✅ Everything is configured and ready! Let me know if you have any issues.

Scott
EOF

echo "✅ Email template ready to send!"
