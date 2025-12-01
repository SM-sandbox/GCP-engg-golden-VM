#!/bin/bash
# Disable Xfce lock screen for current user
# Run this after CRD setup to avoid login prompts

echo "Disabling Xfce lock screen for $(whoami)..."

# Create Xfce config directory
mkdir -p ~/.config/xfce4/xfconf/xfce-perchannel-xml

# Disable screensaver lock
cat > ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
EOF

# Kill any running screensaver
pkill xfce4-screensaver 2>/dev/null || true

echo "✅ Lock screen disabled - you can now connect via CRD without password prompts"
